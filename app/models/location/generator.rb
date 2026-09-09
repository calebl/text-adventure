# Realizes a location: fills in the description and lore the player reads, then
# creates the stub locations the exits lead to. Those stubs are the whole point
# -- when the narrator says three doors lead out, all three have to be real
# records before the player picks one, but only the one they walk through is
# ever written in full.
#
# Generation happens once per place. A realized location is returned untouched,
# which is what makes walking back into a room give you the room you left.
#
# THE PROMPT BLOCKS BELOW HAVE A BENCH: `#people_instructions`,
# `#items_instructions`, `#name_instruction` and `#exits_prompt` are what
# `rake eval:realization` measures, by staging a fixed stub and scoring the
# answer against the records it was built from. Do not edit one of them without
# a stored baseline to judge the change against -- EVALUATION.md -> The
# realization bench is the protocol and `Eval::Realization` is the instrument.
class Location::Generator
  include SanitizesGeneratedText

  # WHAT A ROOM WITH NOBODY IN IT IS TOLD, and it is a constant rather than a
  # line inside `#people_instructions` for one reason: it is the OTHER branch of
  # the count sentence, and `Eval::Realization::Version` has to be able to say
  # which line of a prompt holds the engine's roll without reading two of them
  # out of a heredoc. The heading is the same heading, on purpose -- see that
  # method.
  NOBODY_HERE = <<~PROMPT.rstrip
    ## Who Is Here
    Write NOBODY into this place. There is nobody here, and the description
    should read like somewhere nobody is standing.
  PROMPT

  DETAIL_PENDING = "detail_pending".freeze
  EXITS_PENDING = "exits_pending".freeze

  # A LABEL ON A DOOR THIS ROOM IS ACTUALLY WRITING that `LocationConnection`
  # will not take. A `RecordInvalid` and a type of its own at once: every caller
  # that only ever wanted "the write failed" reads it as what it always was, and
  # #write_exits_serially! can still tell it from every other way a write can
  # fail -- because it is the one failure a retry cannot get past.
  class UnusableExitLabel < ActiveRecord::RecordInvalid; end

  attr_reader :location, :story

  # `location` is a stub -- a Location with a name and a teaser but no
  # description or lore. It may be unsaved; realizing it persists it.
  #
  # `playthrough` is only what the conversation gets filed under (see Chat).
  # Realizing a room is the most expensive thing a move does -- two calls and
  # ~670 output tokens -- so a turn's cost is wrong without it, and the
  # world-building path that has no playthrough simply leaves it out.
  def initialize(location, playthrough: nil)
    @location = location
    @playthrough = playthrough
    @story = location.story
  end

  # Realizes the story's opening location. Story::Generator already created it
  # as a stub from the same call that wrote the preface, so there is nothing to
  # name here -- only to write out in full.
  #
  # THE OPENING ROOM IS REALIZED LIKE EVERY OTHER ROOM, cast included. The
  # captain's ruling of 2026-09-05: *"the opening room should not guarantee at
  # least one person. The protagonist can start by themselves."* So there is no
  # floor here and no second sentence in the prompt -- a world may legitimately
  # open on an empty room, and `rake game:new` says out loud when it did.
  def self.opening(story)
    location = story.opening_location
    raise ArgumentError, "story ##{story.id} has no opening location to realize" if location.nil?

    new(location).realize!
  end

  # A ROOM BEING BORN, AS A CLASS METHOD, so that everything in the app which
  # creates one creates it the same way. `Location::Interior` lays out a whole
  # building of rooms and none of them is named by a model, but every one of
  # them is still a stub with a danger rolled by `Location::Danger` -- and a
  # second place that knew what a new room is would be a second place to forget
  # the roll.
  # AND HOW POPULATED IT IS, WHEN SOMEBODY PICKED A WORD FOR IT. Defaulted to
  # nil, which is the honest answer for every caller that has no word to pass --
  # `Location::Interior` lays out a building nobody named, and a row with no word
  # is one the engine rolls one for (`Location::Population`). Only the exits call
  # has a word, and `#connect_exit!` is what passes it.
  # AND THE FOOTPRINT, WHEN THE PICK THAT NAMED IT SAID IT HAS AN INSIDE. Rolled
  # here rather than by the caller because it is the one draw a room being born
  # makes about its own extent, and a second place that knew how to make it would
  # be a second place to forget the axis: `Roll::FOOTPRINT` is its own kind, so
  # the sides are drawn independently of everything else keyed on this row (see
  # `Roll`'s header for what an axis buys). Nil for every caller with no band --
  # `Location::Interior`'s rooms, `Quest::Deadline`'s places and every stub named
  # by an answer that picked `no inside`.
  def self.create_stub!(story, name:, teaser:, inside: nil, population: nil)
    room = story.locations.create!(name: name, teaser: teaser, detail_level: :stub,
                                   danger: Location::Danger.for_a_new_room(story),
                                   population: population)
    sides = Location::Parameters.from("inside" => inside).footprint(footprint_rng(room))
    room.update!(width: sides.first, depth: sides.last) if sides
    # AND IF THE STORY'S ARC WAS WAITING FOR A PLACE BY THIS NAME, IT NOW HAS
    # ONE. Binding is a side effect of the room being born and never a
    # condition of it (`Quest::Binder`) -- so a model naming an exit, a world
    # mechanic and `Quest::Deadline` all bind on exactly the same terms,
    # because all three come through here. A world with no arc pays one
    # `exists?` and stops.
    Quest::Binder.bind!(room)
    room
  end

  # THE GENERATOR THE SIDES ARE DRAWN FROM, and it is keyed on the ROW because a
  # footprint is a fact about this room and nothing else -- unlike
  # `Location::Population`, which is keyed on the name for reasons its own
  # `.generator_for` gives at length.
  def self.footprint_rng(room)
    Roll.generator(story: room.story_id, sequence: room.id, kind: Roll::FOOTPRINT)
  end

  # Save a successful detail response with the exact engine slots it described,
  # then apply detail, layout, items and people together. Save the accepted exits
  # response before applying its edges. Each checkpoint advances in the same
  # short transaction as its writes; no transaction spans a provider call.
  # A retry reuses paid answers -- every one but an exits answer whose labels the
  # graph refused, which #write_exits_serially! drops rather than replay -- while
  # detail_level stays stub until the final edges and deadline check commit.
  # A completed place is never regenerated.
  # Old realized rows have no checkpoint and remain the authoritative world:
  # their historic missing content cannot be inferred from that flag alone.
  def realize!
    location.save! unless location.persisted?
    GameLock.synchronize("location", location.id) do
      reload_for_generation!
      realize_serially!
    end
  end

  # Different playthroughs can reach the same stub at once. The caller owns
  # its process lock through both model calls and reloads after waiting, so a
  # previously loaded stub cannot overwrite somebody else's completed world.
  # No SQLite transaction is held while a provider answers.
  def realize_serially!
    return location if location.realized? && location.generation_checkpoint.nil?

    write_detail_serially!
    write_exits_serially!

    location
  end
  private :realize_serially!

  # THE INSIDE OF A PLACE, ON FIRST ENTRY. The captain's first ruling of
  # 2026-09-06 -- *the whole interior is laid out on first entry, rooms realized
  # lazily* -- and this is the seam it is triggered through: realizing a stub IS
  # a player arriving somewhere for the first time, and it is the one moment in
  # the app that already means that.
  #
  # `Location#place?` IS THE WHOLE OF THE DECISION, and it is narrow on purpose.
  # It is true only of a row that already carries a FOOTPRINT, which today only
  # a seed file writes -- so no generated world's behaviour changes: every stub
  # this class creates carries no extent and answers false. WHICH generated
  # stubs should become places is a decision about the Iron Gate's scope and is
  # deliberately not made here.
  #
  # BEFORE THE FLIP TO `realized`, in the detail checkpoint's transaction.
  # A layout that raises rolls back every admission and leaves its paid answer
  # available for the next entry to finish. The final exits checkpoint is what
  # exposes the completed place as realized. `Story::Doctor`'s
  # `place_with_a_footprint_and_no_rooms` reports the state anyway, because a
  # database can carry one this code did not write.
  #
  # IT USED TO RUN AFTER THE EXITS CALL, so that the model would not be handed
  # this place's own rooms as somewhere to open a door to. That ordering is no
  # longer what carries the rule and was never strong enough to: a room is now
  # neither OFFERED (`#known_location_names` takes the placed rooms of other
  # places off the list) nor ACCEPTED (`#connect_exit!` refuses one outright),
  # whenever the rooms happen to have been written. A rule about who may be a
  # neighbour holds in an order a rule about which call comes first does not.
  #
  # AND THE ROOMS ARE WIRED TO THIS PLACE'S OWN EXITS, in the same transaction
  # -- #open_the_way_in!, which is the captain's Call 5 of 2026-09-07. The
  # layout has to exist before anything can send anybody into it, so this is the
  # one moment both halves are on the records at once: the doorways the place
  # arrived with, and the rooms they should have been landing on.
  #
  # AN ALREADY-REALIZED PLACE IS NEVER LAID OUT, because `#realize!` returns one
  # untouched -- the "generate once per place" guarantee, which this is downhill
  # of rather than an exception to.
  #
  # AND A PLACE THAT ALREADY HAS ROOMS IS NEVER LAID OUT EITHER, which is the
  # guard that matters to a world file and is `Location::Interior#lay_out!`'s
  # rather than this method's: a file may ship a place as a STUB and still draw
  # every room inside it by hand, so `#place?` is true of it and it is handed
  # over -- and handed straight back, because the rooms are on the records.
  # `test/fixtures/files/a-world-with-an-interior.yml` is exactly that shape,
  # and its author owns its whole floor plan.
  def lay_out_interior!(picks = nil)
    return location unless location.place?

    Location::Interior.lay_out!(location, parameters: Location::Parameters.from(picks))
    open_the_way_in!

    location
  end

  # WHICH SCHEMA THE DETAIL CALL SENDS, and it is the whole of the difference
  # between describing a room and describing a building. `Location::PlaceSchema`
  # is the two prose fields plus the `parameters` block -- the captain's Call 2
  # of 2026-09-07, that the rest of the picks ride on the detail call at first
  # entry -- and `Location::DetailSchema` is what every other room in the game
  # has always been sent, unchanged.
  # AND FOR A ROOM IT IS BUILT FOR THAT ROOM'S OWN COUNT, which is the one
  # schema in the app that is not a constant. The captain's ruling of 2026-09-07:
  # the narrator picks how populated a place is and the engine rolls the count
  # inside that word's band, so `Location::DetailSchema.for_people` requires
  # exactly as many people as `#people_instructions` asks for and the sentence and
  # the field cannot disagree. A BUILDING IS ASKED FOR NO PEOPLE AT ALL -- nobody
  # ever stands in a container -- so the pick reaches rooms and never places, and
  # this branch is where that is true.
  #
  # BOTH READERS GO THROUGH THE MEMOIZED `#cast_registry`, so this and
  # `#detail_prompt` cannot come out of two different rolls whichever order they
  # are called in.
  def detail_schema
    return Location::PlaceSchema if location.place?

    Location::DetailSchema.for_people(cast_registry.allowance)
  end

  # THE WAY IN, MOVED OFF THE BUILDING AND ONTO A ROOM OF IT.
  #
  # THE CAPTAIN'S CALL 5, 2026-09-07: *"the neighbour's doorway lands on the
  # entry room, and the place row is never an endpoint."* Until this method
  # nothing in the app wired a place's doorway to a room inside it, and the one
  # world in the repository with a building had its way in written by hand.
  #
  # WHY IT IS A TRANSPLANT AND NOT A RULE AT WRITING TIME. The doorway is
  # written when a NEIGHBOUR names this place -- long before anybody opens it,
  # when it has no rooms to land on. So the edge is correct when it is written
  # (it is the way in, waiting: `Location#laid_out?`) and becomes wrong the
  # instant there is an inside, which is here. Refusing the edge at #connect_exit!
  # instead would be refusing to let a model name a building.
  #
  # THE LABEL IS CARRIED OVER, NEVER RE-DERIVED. An exterior edge keeps its
  # label -- `Location::Interior`'s two travel-time rules, and the reason is that
  # there is no geometry to derive one from: the quay and the counting room
  # stand in different planes (`Location::Box`). So the distance and the travel
  # method a model picked for "the way to The Rusted Anchor" are the distance
  # and travel method of the way to its taproom.
  #
  # A DOOR IS TWO ROWS, so the pair is dropped and the pair is rewritten, and
  # #connect! is what writes them -- the same writer, the same direction-neutral
  # values, no second spelling of what a doorway is.
  #
  # WHERE IT LANDS WHEN THE ENTRY ROOM IS FULL: the next ground-floor room with
  # a slot (`Location::Interior.doorstep`), because a place can be named by more
  # than one neighbour before anybody opens it and the layout keeps exactly ONE
  # slot free. A second street door on a second ground-floor room is an ordinary
  # building.
  #
  # AND A DOORWAY WITH NOWHERE LEFT TO LAND IS DROPPED, which is the honest
  # answer rather than the tidy one. The alternative is leaving it on the place
  # row, and that is the one shape this whole method exists to make impossible:
  # a party standing in a container, its rooms reachable from nowhere. A
  # building nothing can reach is `Story::Doctor`'s to report
  # (`place_reachable_only_from_inside`) and the neighbour keeps every other way
  # out it had.
  def open_the_way_in!
    doorstep = Location::Interior.doorstep(location)
    return if doorstep.empty?

    ways_in.each do |neighbour, attributes|
      LocationConnection.where(location: location, connected_location: neighbour).delete_all
      LocationConnection.where(location: neighbour, connected_location: location).delete_all

      room = doorstep.find { |candidate| room_for_a_way_in?(candidate) }
      next if room.nil?

      connect!(room, neighbour, attributes)
      connect!(neighbour, room, attributes)
    end
  end

  # EVERY DOORWAY THIS PLACE ARRIVED WITH, as the far end and the label to carry
  # over. Read before anything is deleted, and once, because #open_the_way_in!
  # writes as it goes. A door is two rows and either of them may be the one that
  # exists -- `Story::Doctor` reports a half-written pair (`one_way_connection`)
  # rather than this pretending not to see one -- so both directions are read
  # and the far end is what identifies the doorway.
  def ways_in
    rows = LocationConnection.where(location: location).or(LocationConnection.where(connected_location: location))
                             .order(:id)

    rows.each_with_object({}) do |row, found|
      far = row.location_id == location.id ? row.connected_location : row.location
      found[far] ||= { "distance" => row.distance, "travel_method" => row.travel_method }
    end
  end

  def room_for_a_way_in?(room)
    LocationConnection.from_location(room).count < Location::ExitsSchema::MAX_EXITS
  end

  # What the player reads on arrival, persisted immediately -- and what is lying
  # in it and who is standing in it, out of the same answer.
  #
  # THE ITEMS RIDE ON THIS CALL rather than a third one of their own. A room
  # already costs two calls to realize; asking separately what is on the floor
  # would be a round trip per room to be told "nothing" most of the time, and
  # the two answers could then disagree about the room they describe. See
  # `Location::DetailSchema` for why it is this call and not the exits one, and
  # `Item::Registry` for what happens to the names -- the model proposes, the
  # registry decides, and a name it refuses costs the room its furniture and
  # never its description.
  def write_detail!
    location.save! unless location.persisted?
    GameLock.synchronize("location", location.id) do
      reload_for_generation!
      return location if location.realized? && location.generation_checkpoint.nil?

      write_detail_serially!
    end
  end

  def write_detail_serially!
    checkpoint_detail! if location.generation_checkpoint.nil?
    return location if checkpoint["phase"] == EXITS_PENDING

    detail = checkpoint.fetch("detail")

    location.description = sanitize_string(detail["description"])
    location.lore = sanitize_string(detail["lore"])
    # AND WHAT THE PLAYER WILL CALL IT, for a room of a laid-out place and for
    # nothing else. `Location::RoomName` is the one author of it and the one
    # thing that says no: `#naming` is nil for every other room in the game, and
    # `#accept` answers nil for a name it will not take -- so both of those
    # leave the name the row already has, which for an interior room is
    # `Location::Interior`'s placeholder and for every other room is the name a
    # neighbour or a seed file gave it.
    #
    # WRITTEN ONCE, HERE, like the description and the lore beside it. A
    # realized location is returned untouched by `#realize!`, so nothing renames
    # a room somebody has already walked into.
    location.name = naming.accept(detail["name"]) || location.name if naming

    # AND A ROOM THAT HAS JUST BEEN NAMED IS A ROOM THE ARC MAY HAVE BEEN
    # WAITING FOR. `.create_stub!` binds a room at birth, and a room of an
    # interior is born as a NUMBER (`Location::Interior`'s placeholder) -- so
    # the moment it gets the name a player will read is the second and last
    # moment it can bind. Nothing else in the app renames a location.
    #
    # BEFORE THE SAVE BELOW ON PURPOSE: the binding is deferred to the same
    # transaction, so a layout that raises leaves neither the name nor the arc
    # moved.
    named_room = location.name_changed?

    # THE ROW, THEN THE INSIDE, THEN THE ADMISSIONS -- one transaction.
    # A room is a child of a saved place, so this location has to exist before
    # `Location::Interior` can put anything in it (`#lay_out_interior!` may be
    # handed a stub that was never saved). The checkpoint advances only with
    # every admission, so a retry cannot leave half a cast or change its slots.
    Location.transaction do
      location.save!
      Quest::Binder.bind!(location) if named_room
      lay_out_interior!(detail["parameters"])
      # A building keeps neither items nor people; its rooms admit them when
      # entered. Registry refusals stay refusals, while actual write failures
      # roll back this entire stage for a later retry.
      unless location.laid_out?
        registry.admit!(detail["items"])
        cast_registry.admit!(detail["people"])
      end
      location.update!(generation_checkpoint: checkpoint.slice("chat_id", "prompt", "detail").merge("phase" => EXITS_PENDING))
      # Laying out a building moves its incoming doors onto child rooms. If
      # completion failed after those edges committed, the next entry would
      # bypass the unfinished parent forever. With no exits call left to make,
      # finish inside this same short transaction, or restore the original door.
      finish_realization! if no_exits_call?
    end

    location
  end
  private :write_detail_serially!

  # WHAT MAY COME TO EXIST HERE, and the one thing in the app that creates an
  # `Item`. Held rather than built per call so the room's remaining allowance
  # can be read into the prompt and then enforced against the records.
  def registry
    @registry ||= Item::Registry.new(location)
  end

  # WHO MAY COME TO EXIST HERE. Held rather than built per call for a stronger
  # reason than the item registry's: it rolls the race, age and sex of each
  # person this call may name, and the PROMPT states those before the model
  # answers. A second instance would roll a second set, and the room would be
  # described around one person and written around another.
  def cast_registry
    @cast_registry ||= begin
      slots = checkpoint["slots"]&.map do |slot|
        { race: story.universe.races.find(slot.fetch("race_id")),
          age: slot.fetch("age"), sex: slot.fetch("sex") }
      end
      Character::Registry.new(location, slots: slots)
    end
  end

  # WHETHER THIS ROOM MAY BE NAMED BY THIS CALL, and who decides what it is
  # called if it is. Nil for everything that is not a room of a laid-out place
  # still carrying one of its numbers, which is the gate `Location::RoomName.for`
  # owns -- both halves of it -- so that neither the prompt nor the write has one
  # of its own.
  #
  # `defined?` AND NOT `||=`, because nil is the ordinary answer and the common
  # case is the one that must not pay for the question twice: `#name_instruction`
  # asks on the way in and `#write_detail!` asks again on the way out.
  def naming
    return @naming if defined?(@naming)

    @naming = Location::RoomName.for(location)
  end

  # The ways out, as stub neighbours plus connection rows in both directions,
  # in one transaction so a room never keeps some of its exits and not others.
  #
  # THE FLOOR is the second pass. A room with no way out at all is worse than a
  # room with one it should not have, so if every way out the model named was a
  # written room this cannot open a door into (see #connect_exit!), they are
  # taken anyway rather than sealing the player in. Only reachable for a room
  # that was not realized by being walked into -- an arrival already has its
  # way back, so the first pass can never leave it with nothing.
  #
  # THE FLOOR LIFTS THE WRITTEN-ROOM REFUSAL AND NOTHING ELSE. A name that is a
  # room inside another place, or a neighbour already at its own cap, is a name
  # #connect_exit! cannot honour on any pass -- taking it would break an
  # invariant rather than bend a preference. So a room every one of whose named
  # ways out was one of those still ends with none, and that is the state
  # `Story::Doctor` reports and `Story::Repair` finishes by calling this again.
  #
  # AN INTERIOR ROOM'S WAYS OUT ARE THE ENGINE'S, AND THE CALL IS NOT MADE.
  # `Location::Interior` already decided every door and every stair a room has,
  # from geometry and one seeded roll, under guarantees no prompt can carry:
  # every room reachable from the entry, no room past
  # `Location::ExitsSchema::MAX_EXITS`, a door only between two rooms that share
  # a WALL, a stair only between two rooms that stand over each other, and one
  # slot kept free on the entry room for the way IN. Every exit a model could
  # name here breaks one of those. A sibling that meets this room at a corner is
  # a door through a corner (`Location::Box#shares_a_wall?` is false and
  # `Story::Doctor`'s `door_between_rooms_that_share_no_wall` reports one). An
  # invented name is worse: `.create_stub!` writes no `parent_location`, so it
  # would be a row at the OUTERMOST level wired to a room two doors deep inside
  # a building -- a shape nothing in the app can produce and nothing downstream
  # reads. And either one spends the entry room's reserved slot on somebody
  # else's door.
  #
  # SKIPPED RATHER THAN ANSWERED-AND-IGNORED, which is the choice between the
  # two and the reason this is here rather than a refusal in #connect_exit!: an
  # answer that would be thrown away whole is an answer that should not be
  # bought, so this saves the model call and not just the writes. NO PROMPT TEXT
  # MOVES either way -- the exits prompt is not BUILT for a room, rather than
  # built differently for one, so nothing a baseline was measured on changes.
  #
  # SO A ROOM CAN END WITH NO WAY OUT AT ALL, and the single room of a one-room
  # interior does until slice 4 wires the way in. `Story::Doctor` reports it as
  # `location_has_no_exits` and `Story::Repair` calls this and is told nothing
  # was written, which is the honest answer: the way into a building is not a
  # thing a model may name.
  # AND A PLACE THAT HAS AN INSIDE IS NOT ASKED EITHER, for the mirror image of
  # the reason a room of one is not. A laid-out place's ways out ARE its rooms'
  # ways out -- #open_the_way_in! has just moved every doorway it had onto the
  # entry room, on the captain's Call 5 that the place row is never an endpoint
  # -- so an exit named here would be a door back onto the container, written by
  # the very call that runs a line after the transplant. `Story::Doctor` reports
  # one (`connection_terminating_on_a_place`); this is what stops the app
  # writing it. SKIPPED RATHER THAN ANSWERED-AND-IGNORED, on the same terms:
  # the call is not bought, and no prompt text moves for any other room.
  def write_exits!
    location.save! unless location.persisted?
    GameLock.synchronize("location", location.id) do
      reload_for_generation!
      return realize_serially! if checkpoint["phase"] == DETAIL_PENDING

      write_exits_serially!
    end
  end

  # THE ACCEPTED EXITS ANSWER IS A PROVISIONAL RECEIPT, and the writer is what
  # decides whether it stands. Storing it before anything is written is what
  # stops a crash between the answer and the edges paying for the same call
  # twice -- but an answer carrying a label the graph will not take would then
  # be replayed by every retry, and the room could never be finished at all.
  #
  # SO THE ONE FAILURE THAT DISCARDS IT IS THE ONE A RETRY CANNOT GET PAST: a
  # label on a door this room was actually writing (`UnusableExitLabel`, raised
  # by #connect!). The transaction rolls the graph back, the answer is dropped,
  # and the next entry asks for exits again -- for exits only, since its detail
  # checkpoint is untouched. EVERY OTHER FAILURE KEEPS THE ANSWER, because the
  # same answer can be applied by a retry that costs no model call: a lost
  # connection, a busy database, a finalization that raised.
  #
  # WHICH DOORS GET WRITTEN IS NOT PREDICTED HERE, AND THAT IS THE WHOLE RULE.
  # The writer is sequential -- #connect_exit! judges a proposal against the
  # records as they stand when it reaches it, this room's allowance included,
  # and #connect! writes nothing at all for a pair that already exists -- so a
  # label is judged at the one moment its own row is about to be created and
  # never before. A second reading of that policy, run over the whole answer
  # against the graph as it was, refused proposals the writer then dropped and
  # failed realizations the player had already paid for: a way back named again
  # with a bad label, a written neighbour this room cannot open onto, a second
  # spelling of a door just written, a proposal past this room's allowance.
  def write_exits_serially!
    # ALREADY FULL, so there is nothing to ask and nothing to spend. A stub can
    # arrive at the cap before anybody walks into it: a world file seeds edges,
    # and every neighbour that named this place on its way to being realized
    # wrote one. See Location::ExitsSchema::MAX_EXITS.
    return finish_realization! if no_exits_call?

    exits = if checkpoint.key?("exits")
      checkpoint.fetch("exits")
    else
      Array(ask(Location::ExitsSchema, exits_prompt)["exits"]).tap do |answer|
        location.update!(generation_checkpoint: checkpoint.merge("exits" => answer)) if checkpoint["phase"] == EXITS_PENDING
      end
    end

    Location.transaction do
      exits.each { |attributes| connect_exit!(attributes) if room_for_exits.positive? }
      exits.each { |attributes| connect_exit!(attributes, into_written: true) } unless location.exits.exists?
      finish_realization!
    end

    location
  rescue UnusableExitLabel
    discard_exits_answer!
    raise
  end
  private :write_exits_serially!

  # WHETHER THIS IS A ROOM INSIDE A LAID-OUT PLACE, which is the one question
  # #write_exits! asks before deciding whether there is anything to ask a model.
  # BOTH HALVES ARE REQUIRED: a box read in a parent's own plane. A box with no
  # parent is three numbers with nothing to measure them against
  # (`Story::Doctor#boxes_with_no_parent`) and is a room of nothing, and a
  # parent with no box is ordinary containment -- a district a street is in --
  # which no interior laid out and whose exits are still the model's to name.
  def interior_room? = location.placed? && location.parent_location_id.present?

  # HOW MANY MORE WAYS OUT THIS ROOM MAY HAVE. Read from the records on every
  # check rather than counted once, because `#connect_exit!` writes as it goes
  # and a budget worked out before the loop would not notice. Naming a
  # neighbour this room already reaches costs nothing -- `#connect!` returns
  # early on an edge that exists -- so a no-op does not spend the allowance.
  def room_for_exits
    [ Location::ExitsSchema::MAX_EXITS - location.exits.count, 0 ].max
  end

  # ONE conversation for both calls, and that is why persistence is per agent
  # rather than per call: the exits call is asked in the context of the
  # description the same model just wrote, so the two exchanges are one
  # conversation and the stored row is what was actually sent.
  def agent
    @agent ||= begin
      conversation = Chat.find_by(id: checkpoint["chat_id"]) if checkpoint["chat_id"]
      resumed = BaseAgent.new(purpose: "location", playthrough: @playthrough, chat: conversation).with_instructions(system_prompt)
      # A world's unfinished room outlives the playthrough that paid for it.
      # If that game's audit chat was deleted, restore the accepted exchange
      # exactly, without asking again or copying its original billed tokens.
      if checkpoint["prompt"] && !detail_history?(conversation)
        resumed.add_message(role: :user, content: checkpoint.fetch("prompt"))
        resumed.add_message(role: :assistant, content: checkpoint.fetch("detail"))
        if (recorded = resumed.recorded_chat)
          location.update!(generation_checkpoint: checkpoint.merge("chat_id" => recorded.id))
        end
      end
      resumed
    end
  end

  def system_prompt
    <<~PROMPT
      You build the rooms of a text adventure one at a time. You write places a
      player can stand in and walk out of: concrete, specific, and consistent
      with the world they belong to. Every exit you name is somewhere the player
      could actually go.

      DO NOT INCLUDE EMOJIS IN YOUR RESPONSE.
    PROMPT
  end

  # A BUILDING GETS A PROMPT OF ITS OWN, and the ordinary one below is not
  # touched -- not one byte, which is `#geometry_facts`' rule applied to a whole
  # template: every room in the game still sends the prompt a stored baseline was
  # measured on. A building is a different ask (what kind of place is this, and
  # what should the engine build inside it) with a different schema and no items,
  # no people and no name, so folding the two into one template with three
  # conditional blocks would be a template neither case reads plainly.
  def detail_prompt
    return place_prompt if location.place?

    <<~PROMPT
      #{story_context}

      ## The Place
      name: #{location.name}
      teaser: #{location.teaser}
      #{geometry_facts}
      ## Instructions
      Write this place out in full.
      - The description is what the player reads on arrival. Address them as "you"
      - Describe what is here now, not the history -- the history is the lore
      - Stay consistent with the universe and with the teaser above
      - Respect the stated length of each field#{name_instruction}

      #{items_instructions}

      #{people_instructions}
    PROMPT
  end

  # WHAT A BUILDING IS ASKED, and the second half of the captain's Call 7 of
  # 2026-09-06: *"the engine actually generates the location, then it is handed
  # back to a narrator to describe."* This is the call before that one -- the
  # place is described here and its parameters are picked here, and the engine
  # builds the inside out of them in the same transaction.
  #
  # IT SAYS WHAT THE ENGINE WILL DO WITH THE ANSWER, which is the cheap half of
  # the standing constraint: a model told that the game draws the floor plan
  # itself is a model with no reason to describe one, and a description that
  # invents a staircase anyway costs a sentence rather than a room. Nothing here
  # is a guarantee -- `Location::Interior` decides every wall from integers and
  # one seeded roll, and never reads a word of this.
  #
  # AND IT ASKS FOR NOBODY AND NOTHING, because the rooms are where a person
  # stands and a thing lies. `Location::PlaceSchema` has no field for either, so
  # this is the prompt agreeing with the schema rather than a rule the answer
  # could break.
  def place_prompt
    <<~PROMPT
      #{story_context}

      ## The Place
      name: #{location.name}
      teaser: #{location.teaser}

      ## Instructions
      Write this place out in full. It is a BUILDING -- somewhere with rooms
      inside it that a player walks into and moves around in.
      - The description is what the player reads as they come in. Address them as "you"
      - Describe what is here now, not the history -- the history is the lore
      - Stay consistent with the universe and with the teaser above
      - Do NOT describe the floor plan: how many rooms there are, where the stairs
        are and which door leads where are the game's to decide, out of the answers
        below, and it will tell you room by room as the player reaches them
      - Do not name anybody standing here and do not list anything lying here.
        People and things belong to the rooms, and each room is written as it is
        reached
      - Respect the stated length of each field

      #{parameters_instructions}
    PROMPT
  end

  # THE PICKS, AS A BLOCK OF DIRECTION RATHER THAN A LIST OF FIELDS -- the
  # closed lists themselves are on `Location::PlaceSchema`, so this says what
  # they are FOR and what the quiet answer is. The captain's own words for what
  # he wanted: *"we should provide some direction on how to make that
  # decision."*
  def parameters_instructions
    <<~PROMPT.rstrip
      ## What Kind Of Building This Is
      The game lays the inside out itself -- every room, every door, every stair
      -- from the answers to these, and then writes each room as the player
      reaches it. You are choosing what KIND of place this is, not drawing it.
      - Answer for the place you have just described and for the story it stands in
      - Every one of them can be left out, and the quietest answer is usually the
        right one: one floor, nothing underneath, nothing dangerous, nothing that
        hurts you
      - A HAZARD is not atmosphere. It takes hit points off everybody who walks
        through those rooms, every turn in some cases, so pick one only for a
        place that really is flooded, unlit, silent or airless
      - A GRADIENT is only worth saying when the place itself makes it true: a
        cellar that gets worse the further down you go, a tower that gets worse
        the higher you climb
    PROMPT
  end

  # WHERE THIS ROOM IS, AS FACTS THE ENGINE HAS ALREADY DECIDED -- how big it
  # is, which storey of which place it stands on, which wall each door is in and
  # where each one leads. `Location::Plan` is the one author of them, so the
  # room writer and the narrator are told the same walls
  # (`Playthrough::Moment#narration_context`).
  #
  # IT IS THE INFORM HALF AND NOT THE VERIFY HALF, which is the standing
  # constraint's own division of labour and is worth stating on the one prompt
  # block that could be mistaken for a guarantee. The doors are already
  # `LocationConnection` rows and `#write_exits!` asks a model for none of them,
  # so a description that invents a third door changes nothing about where the
  # player can walk. What it costs is a room whose prose argues with its own
  # map, which `Story::Audit::Prose`'s geometry predicates read and
  # `Eval::Realization::Scorer` scores.
  #
  # EMPTY FOR EVERY ROOM THAT IS NOT ONE, and empty means the prompt is the one
  # a baseline was measured on, character for character: `Location::Plan.for`
  # answers nil for a place, for an ordinary outermost room, and for anything
  # else with no box read in a parent's plane, and the blank line the block
  # stands on is the blank line that was already there.
  def geometry_facts
    plan = Location::Plan.for(location)
    return "" if plan.nil?

    <<~PROMPT.rstrip
      ## Where This Room Is
      The game's own records of this room, already decided and not yours to
      change. Write the room around them: do not contradict a measurement, and
      do not give it a way out this list does not have.
      #{plan.to_prompt}
    PROMPT
  end

  # WHAT THE MODEL IS TOLD WHEN THE ROOM STILL NEEDS A NAME, and it is one
  # bullet on the end of the instructions the room already has rather than a
  # block of its own.
  #
  # EMPTY FOR EVERY ROOM THAT IS NOT ONE, and empty means the prompt is the one
  # a baseline was measured on, character for character -- `#geometry_facts`'s
  # rule, and the reason this appends to the last bullet instead of standing on
  # a line: a block of its own would add a blank line to every prompt in the
  # game the day it was empty. Only a room of a laid-out place still called one
  # of its numbers has a name worth replacing (`Location::RoomName.for`, which
  # asks both); a room a neighbour named, or one a seed file named by hand,
  # already has a name a player may have typed.
  #
  # IT IS THE INFORM HALF AND NOT THE VERIFY HALF. Every rule stated here is
  # one `Location::RoomName#refusal_for` enforces afterwards whatever comes back
  # -- the place's name kept out of it (`#repeats_place?`), no comma, nothing
  # this world has already spoken for -- so this is here to raise the odds and
  # never to carry the guarantee. The standing constraint, applied to a name.
  #
  # AND IT NAMES WHAT IS ALREADY TAKEN, because a refusal after the call is a
  # room that kept its placeholder over a collision it was never shown --
  # `#items_instructions`' own argument, and the same trade.
  def name_instruction
    return "" if naming.nil?

    place = naming.place.name
    <<~PROMPT.rstrip.prepend("\n")
      - NAME THIS ROOM. It is one room inside #{place}. The player reads the room and
        the place together -- "the <your name> of #{place}" -- so name the ROOM only,
        and never put the place's own name into it. A short noun phrase carrying the
        article English wants on it, 2 to 4 words: "the counting room", "the cold
        store", "the harbourmaster's office". Name it for what the floor plan above
        says this room is and for what you have just described standing in it. Never
        a comma in it#{named_rooms_note}
    PROMPT
  end

  # The rooms of this place that have already been written and named, so the
  # model is not offered a name the engine is about to refuse. The placeholders
  # are left off (`Location::RoomName#named_siblings`): a fourteen-room building
  # would otherwise spend fourteen lines saying "not the numbers", which nothing
  # was ever going to propose.
  def named_rooms_note
    named = naming.named_siblings
    return "" if named.empty?

    ". Rooms of #{naming.place.name} that are already named, so do not reuse one: #{named.join("; ")}"
  end

  # WHAT THE MODEL IS TOLD ABOUT WHO IS IN THIS ROOM. Two things, and the second
  # is what keeps this cheap: HOW MANY PEOPLE THERE ARE, and WHO THEY ALREADY
  # ARE. Race, age and sex are rolled by `Character::Registry#slots` before this
  # prompt is built and stated here per slot, so the model writes a person the
  # engine has already decided rather than deciding one -- the rule
  # `Character::Generator` states as *asking for a value the prompt just
  # supplied is a decision bought twice.*
  #
  # THE COUNT IS A FACT AND NOT A CEILING, which is what the captain's ruling of
  # 2026-09-07 changed here. This block used to say "AT MOST n" and, two lines
  # below it, *"NOBODY is the right answer for most rooms"* -- a ceiling and a
  # nudge to leave it empty, in the same breath. Four of six realization answers
  # on record then named nobody in rooms whose prompt had offered two slots. Both
  # sentences are gone: the model has already picked how populated this place is,
  # on the exits call of the room next door (`Location::ExitsSchema`), the engine
  # has already rolled the number that word means
  # (`Location::Population`), and what is left to say is how many people to write
  # and who they are. `Location::DetailSchema.for_people` requires exactly that
  # many, so the sentence and the schema are the same statement twice.
  #
  # NOUGHT IS ITS OWN SENTENCE AND KEEPS THE HEADING, and both halves of that
  # matter. A room the pick called empty is a room to be described with nobody in
  # it, and saying so is a shorter answer rather than a refused one -- so the
  # array stays optional at nought (see that schema on why an empty required
  # array reads as an omitted field to `BaseAgent#missing_schema_keys`). The
  # heading is kept over both branches so that the count-bearing line is always
  # the line under `## Who Is Here`, which is what
  # `Eval::Realization::Version` scrubs to tell a prompt version from the
  # engine's own dice.
  def people_instructions
    wanted = cast_registry.allowance

    return NOBODY_HERE if wanted.zero?

    <<~PROMPT.rstrip
      ## Who Is Here
      Write EXACTLY #{wanted} #{"person".pluralize(wanted)} who #{wanted == 1 ? "is" : "are"} in this place right now.
      - Anyone you write is somebody the player can walk up to and talk to, so they
        have to have a reason to be standing here and something they want
      - Do not write the player, and do not write somebody passing through
      - Never give them the name of a place, of a thing, or any name already
        spoken for above

      #{slot_details(wanted)}
    PROMPT
  end

  # The people the engine has already decided on, one line each, in the order
  # the answer's entries are read back in. `#slots` is already exactly as long
  # as the count (`Character::Registry`), so the `first` is a belt on a
  # statement made one method up rather than a narrowing of anything.
  def slot_details(wanted)
    lines = cast_registry.slots.first(wanted).each_with_index.map do |details, index|
      race = details[:race]
      # `details[:sex]` is the STORED value rather than the enum key -- "trans
      # woman", not "trans_woman" -- so the line reads as English. Same reason
      # `Character#sex_label` exists and the same value `Character::Generator`
      # states in its own predetermined block.
      "  the #{(index + 1).ordinalize} is #{race&.name}, about #{details[:age]}, #{details[:sex]}"
    end

    "Who they are is already decided. Write these people and do not change them:\n#{lines.join("\n")}"
  end

  # WHAT THE MODEL IS TOLD ABOUT THE FLOOR OF THIS ROOM. It is asked for at
  # most what is left of the room's allowance and told the two names it must
  # not reuse, because both of those are things the engine will refuse
  # afterwards anyway (`Item::Registry`) -- and a refusal after the call is a
  # room with less in it than the model thought it had furnished. Saying so up
  # front is what stops one being spent.
  #
  # A room already at its cap, or a world at its own, is asked for nothing at
  # all: the sentence says zero and the schema's array can honestly come back
  # empty.
  def items_instructions
    allowance = [ registry.room_for_items, registry.world_for_items ].min

    return "Do not list any items: this place already holds everything it can." if allowance.zero?

    <<~PROMPT.rstrip
      ## What Is Lying Here
      List AT MOST #{allowance} portable thing#{"s" unless allowance == 1} a player could pick up and carry away.
      - Nothing is the right answer for most rooms. An empty list is a complete answer
      - Only loose, portable things. Not the door, not the floor, not the machinery
        bolted to it -- something a person could put in a pocket or under an arm
      - Each one must be consistent with the description you just wrote, and worth
        the player noticing
      - If a thing has WRITING on it -- a note, a letter, a handbill, a label, a
        docket, a page, a sign -- mark it readable and WRITE OUT WHAT IS WRITTEN
        ON IT, exactly as it appears on the thing. The words themselves, not a
        description of them, and short enough to finish -- a few words, a line,
        or a few short lines. The game keeps those words and a player reading it
        twice reads the same ones
      - Never name it after a person or after a place#{known_names_note}
    PROMPT
  end

  # WHY THE WRITING IS ASKED FOR HERE AND NOT LATER. A thing marked readable with
  # no words is a thing whose words the first read has to pay a round trip for
  # (`Item::Inscriber`), written by a model that has not seen this room. Measured
  # before this line existed: four live realizations named three readable things
  # and supplied an inscription for none of them, because nothing asked. The
  # field is optional in the schema and has to be, so the sentence is what makes
  # it the ordinary answer.

  # The names already spoken for in this story, so the model does not spend an
  # item or a person on one. Truncated rather than unbounded: this rides on a
  # prompt sent once per room, and a world with two hundred names in it would
  # pay for the whole list to say "not these". Read by both instruction blocks,
  # because both registries refuse a name the other's records already hold.
  def known_names_note
    taken = (story.characters.order(:id).limit(20).pluck(:fullname) +
             registry.story_items.order(:id).limit(20).pluck(:name)).compact_blank
    return "" if taken.empty?

    ". Already spoken for in this story, so do not reuse: #{taken.join(", ")}"
  end

  def exits_prompt
    <<~PROMPT
      Now list the ways out of #{location.name}.

      #{already_reachable_note}

      ## Places That Already Exist In This Story
      Reuse a name from this list when an exit leads somewhere already known.
      Only invent a name when the exit leads somewhere genuinely new.
      A place marked (already written) has had its own ways out written down
      already, so naming it here would open a door it does not have: leave it
      out and name somewhere new instead.
      #{known_location_names.presence || "None yet."}

      ## Instructions
      - Name AT MOST #{room_for_exits} #{"way".pluralize(room_for_exits)} out. That is what is left of this
        room's #{Location::ExitsSchema::MAX_EXITS}, not a target: fewer is a better answer than a door
        nobody needed
      - Each exit is somewhere the player can reach directly from #{location.name}
      - One way out is a complete answer. A dead end, a cell, the bottom of a
        shaft: if the only way out is back the place the player came from, list
        that place and nothing else. Never invent a passage to reach a second
      - When there is more than one, give the player a reason to prefer one
        over another
      - Do not list #{location.name} itself
      - Say which of them have an INSIDE, and say NO INSIDE for almost all of
        them. Saying anything else makes the game build a whole floor plan of
        rooms in that place and send the player walking through them, so it is
        only ever right for a BUILDING somebody goes in at a door -- an inn, a
        keep, a counting house, a warren. A road, a shore, a clearing, a bridge,
        a square, a cave mouth, a stair, a courtyard: no inside. A room, an
        office, a hall, a chamber: no inside either, because those are already
        somewhere the player stands. Where it really is a building, pick the size
        it would really be rather than the most interesting one
      - Distance and travel method must be consistent with the description you
        just wrote, and must be true in both directions -- the way back is the
        same edge
      - Say how populated each place is, in one of the words offered. A place is
        peopled by what it is FOR: a market, a taproom, a guardhouse, a
        workshop, a shrine somebody keeps -- somewhere with a reason for
        somebody to be standing in it. A place is empty when nothing is asked of
        anybody there: a cellar, a back stair, a stretch of road, a room that is
        locked, a place the story has already emptied. Neither answer is the
        safe one
      - Respect the stated length of each field
    PROMPT
  end

  private

  def checkpoint = location.generation_checkpoint || {}

  def no_exits_call? = interior_room? || location.laid_out? || room_for_exits.zero?

  # A caller may have inspected the schema or prepared an agent before waiting
  # for the room's lock. A durable checkpoint outranks those earlier rolls and
  # that earlier conversation, including when the same generator is retried.
  def reload_for_generation!
    location.reload
    return if location.generation_checkpoint.nil?

    %i[@agent @registry @cast_registry @naming @open_step].each do |name|
      remove_instance_variable(name) if instance_variable_defined?(name)
    end
  end

  def detail_history?(conversation)
    conversation&.exchange_messages&.any? { |message| message.role == "assistant" && message.content_raw == checkpoint["detail"] }
  end

  # Check the required prose against the destination's real validation before
  # making it a durable retry receipt. An unusable answer must remain payable
  # again; a good one and the slots it described must not be rolled again.
  def checkpoint_detail!
    schema = detail_schema
    prompt = detail_prompt
    detail = ask(schema, prompt)
    candidate = location.dup
    candidate.assign_attributes(description: sanitize_string(detail["description"]),
                                lore: sanitize_string(detail["lore"]), detail_level: :realized)
    candidate.validate!
    slots = location.place? ? [] : cast_registry.slots.map do |slot|
      { "race_id" => slot.fetch(:race).id, "age" => slot.fetch(:age), "sex" => slot.fetch(:sex) }
    end
    conversation = agent.recorded_chat if agent.respond_to?(:recorded_chat)
    location.update!(generation_checkpoint: {
      "phase" => DETAIL_PENDING, "detail" => detail, "prompt" => prompt, "slots" => slots,
      "chat_id" => conversation&.id
    }.compact)
  end

  # A PAID EXITS ANSWER THIS ROOM WILL NEVER GET PAST, dropped after its writes
  # have rolled back so the next entry asks for a different one. Read from the
  # row rather than from memory: the rollback is what this runs after. A repair
  # of an old realized room has no checkpoint to drop and never had an answer
  # stored, which is the nil case.
  def discard_exits_answer!
    location.reload
    return if location.generation_checkpoint.nil? || !location.generation_checkpoint.key?("exits")

    location.update!(generation_checkpoint: location.generation_checkpoint.except("exits"))
  end

  # Edge writes, the completed flag and deadline placements share one commit.
  # Direct repairs of an old realized room have no checkpoint to finish.
  def finish_realization!
    return location unless checkpoint["phase"] == EXITS_PENDING

    Location.transaction do
      location.update!(detail_level: :realized, generation_checkpoint: nil)
      Quest::Deadline.after_realizing!(location)
    end
    location
  end

  def ask(schema, prompt)
    agent.with_schema(schema).ask(prompt).content
  end

  # THE ARC BLOCK IS APPENDED RATHER THAN INTERPOLATED INTO THE HEREDOC, and
  # that is a measurement decision rather than a style one. An empty
  # `#{arc_block}` on a line of its own still emits that line, so every world
  # with no arc would have sent one extra blank line -- which moved the
  # realization bench's prompt digest for all nine shapes and would have cost a
  # bench round to measure a newline. Appending keeps the prompt those worlds
  # send byte-for-byte identical, which is what lets the stored baseline go on
  # being a baseline for them.
  def story_context
    <<~CONTEXT + arc_block
      ## Universe Details
      #{story.universe.prompt_details(:place)}

      ## Story Details
      title: #{story.title}
      genre: #{story.genre}
      preface: #{story.preface}
      summary: #{story.summary}
    CONTEXT
  end

  # WHERE THE STORY IS GOING, IN ONE BLOCK, IN THE ONE PLACE BOTH CALLS READ.
  #
  # THE INFORM HALF OF THE ARC, and it is only the inform half. The captain's
  # standing constraint is *gate the state, inform the prose*: this is a prompt,
  # so nothing may rest on it: `Quest::Deadline` is the verify half and it does
  # not care whether this worked. A world where the model never once takes the
  # hint still reaches its own ending; what this buys is that it reaches it as
  # fiction rather than as an engine placement.
  #
  # ONE BLOCK AND NOT THREE, which is what makes it cost nothing per room.
  # `#story_context` is sent by BOTH realization calls -- the detail call and
  # the exits call share one `BaseAgent` conversation -- so a single block
  # reaches the seam that names a way out, the seam that writes a person into a
  # room, and the seam that puts a thing on the floor. There is no second call
  # and no per-seam prompt.
  #
  # IT NAMES THE NEXT OPEN STEP AND NOT THE ARC. Three or four beats would be an
  # outline, and `Story::Generator`'s closing sentence -- *"Leave the ending
  # open. You are starting a story, not outlining one."* -- is a rule about this
  # world that a later call must not quietly reverse.
  #
  # AND IT NEVER CARRIES THE CONCLUSION, which is where this departs from the
  # arc design's own draft (`data/ta-quest-progress-scout/report.md` §5.3 puts a
  # `conclusion:` line in this block). The captain's Call 4 of 2026-09-06 gave
  # the reasoning against it one prompt over: a model told how the story ends
  # writes TOWARD that ending, and a room described as though the ending were
  # near is prose about a record the engine does not have. The step is a fact --
  # the world must come to contain this thing -- and the ending is not one yet.
  #
  # THE STEP IS THE MAIN ARC'S FIRST UNREACHED ONE, asked WITHOUT a playthrough:
  # realization is the WORLD growing, not one player's progress through it, and
  # two people playing one world must not get two different rooms. So it is the
  # arc's own first open beat rather than `Playthrough::Arc#next_step`'s
  # per-game answer, and that is the one place in the app where the two
  # deliberately differ.
  #
  # EMPTY FOR EVERY WORLD WITH NO ARC, which is every world generated before
  # `Quest::Generator` shipped and every seed file with no `quests:` block -- so
  # those worlds send the prompt they always sent, byte for byte, and the stored
  # realization baseline stays a baseline for them.
  def arc_block
    step = open_step
    return "" if step.nil?

    <<~ARC
      \n## Where This Story Is Going
      next: #{step.summary}
      #{wanted_line(step)}
      #{step.teaser.presence&.then { |line| "#{line}\n" }}If this room is a natural place for it, this is where it
      comes from; if it is not, leave it and somewhere else will do. Do not bend
      this room to fit it.
    ARC
  end

  # WHAT THE WORLD IS SHORT OF, in the vocabulary of the seam that can supply
  # it: a PLACE is something the exits call names, a PERSON is somebody the
  # detail call writes into the room, a THING is something it puts on the floor.
  # Said as the kind rather than as the trigger, because `reach_location` is the
  # engine's word and a model has no use for it.
  def wanted_line(step)
    case step.trigger_kind
    when "reach_location"
      %(This story needs a PLACE called "#{step.target_name}", somewhere a player can walk to. ) +
        "There is no such place in this world yet."
    when "speak_to"
      %(This story needs a PERSON called "#{step.target_name}", standing somewhere a player can reach. ) +
        "There is nobody of that name in this world yet."
    when "hold_item"
      %(This story needs a THING called "#{step.target_name}", lying somewhere a player can pick it up. ) +
        "There is no such thing in this world yet."
    end
  end

  # THE ARC'S OWN FIRST OPEN BEAT -- the lowest-positioned step of the main arc
  # that the world has not grown a row for. Nil for a world with no arc, for a
  # doomed one, and for an arc whose every beat is already bound, which is the
  # state a world reaches once it contains everything its story asked for.
  #
  # UNBOUND AND NOT UNREACHED: this asks what the WORLD is missing, and a step
  # bound to a row is a step the world has answered however far any player has
  # got. `Playthrough::Arc#next_step` is the per-game question and is the
  # narrator's; this is the world's and is the generator's.
  def open_step
    return @open_step if defined?(@open_step)

    arc = story.main_quest
    @open_step = arc.nil? || arc.doomed? ? nil : arc.steps.detect { |step| step.unbound? && step.wants_a_row? }
  end

  # The places the model may reuse a name from, with the written ones marked.
  # A room that has been written has already said what its ways out are, so
  # naming it here is asking for a door it does not have; the engine refuses
  # that edge in #connect_exit! either way, and saying so up front is what
  # stops the model spending an exit on one.
  # WHAT THIS ROOM CAN ALREADY REACH, said before the model is asked for more.
  # A room walked into has its way back, and a seeded one can have several
  # edges: without this the model names four ways out of a room that already
  # had two, and the player stands somewhere with six.
  def already_reachable_note
    reachable = location.exits.order(:id).pluck(:name)
    return "This room has no ways out yet." if reachable.empty?

    "## Where This Room Already Leads
" \
      "#{reachable.map { |name| "- #{name}" }.join("\n")}\n" \
      "Those exist already and do not need naming again. Do not contradict them."
  end

  # A PLACED ROOM OF ANOTHER PLACE IS NOT ON THE LIST, and that is the whole of
  # what comes off it: a row carrying a BOX, read in some other place's plane.
  # This is the half of the rule that costs a sentence; the half nothing depends
  # on the model for is #connect_exit!'s matching refusal. `#rooms_elsewhere` is
  # the one statement of it, asked once as a query and once as a predicate.
  #
  # KEYED ON PLACEMENT AND NOT ON `parent_location_id` EQUALITY, and the
  # difference is a shape a world file may legitimately write: PLAIN
  # CONTAINMENT, a `parent` with no box -- a district a street sits in, which
  # `WorldSeed::Loader#validate_one_parent!` allows and `WorldSeed::Exporter`
  # round-trips. Nothing laid a district out, so its children are ordinary
  # places whose ways out are still the model's to name. Keyed on parent
  # equality instead, a street inside a district would be offered nothing but
  # the district's other streets -- "None yet." for the only child of one -- and
  # would then be refused every outermost name it reused, which is a realized
  # room with no way out of it.
  #
  # THIS IS NOT A PROMPT CHANGE WANTING A STORED BASELINE, and it is worth
  # saying so here so nobody later reads it as one. Nothing in the app wrote a
  # `parent_location` before `Location::Interior` did, and no world any stored
  # `db/eval/` baseline was measured on carries one -- so for every story those
  # baselines saw there is no placed room to take off the list and this selects
  # all of them. It cannot have moved the text they were measured against.
  def known_location_names
    story.locations.where.not(id: location.id).where.not(id: rooms_elsewhere.select(:id))
         .order(:id).map { |place| known_location_line(place) }.join("\n")
  end

  # THE ROOMS OF SOMEBODY ELSE'S INTERIOR: placed -- all five columns, so read
  # in a parent's own plane -- inside a place that is not the one this location
  # is in. A room of THIS location's own parent is not one of them, so a sibling
  # stays nameable if a later slice ever asks a room for a way out.
  def rooms_elsewhere
    story.locations.with_a_box.where.not(parent_location_id: [ nil, location.parent_location_id ])
  end

  def known_location_line(place)
    return place.name unless place.realized? && !connected?(place)

    "#{place.name} (already written -- do not open a new way into it)"
  end

  # An exit becomes a stub neighbour plus a connection in both directions.
  # Reusing an existing location by name is what stops realizing A -> stub B,
  # then realizing B, from creating a second A alongside the first.
  #
  # A REUSED NAME THAT IS ALREADY WRITTEN IS NOT A NEW EXIT. Realizing this
  # room would otherwise add a way out to a room whose description has already
  # been written and already said what its ways out are: a supply closet whose
  # prose reads "there is no other door" grew a second one the moment the
  # hallway next to it was realized and the model reused the closet's name. The
  # edge is dropped in BOTH directions, because it is one edge.
  #
  # What decides is the connection and not the detail level, so the two cases
  # that have to stay legal do: the way back, written when this room was still
  # a stub, and a written place the player can already reach from here. Only an
  # edge that did not exist before is refused. `into_written:` is the floor in
  # #write_exits! asking for that refusal to be lifted.
  #
  # A DOOR NEVER CROSSES THE WALL OF A BUILDING, and it takes BOTH this method
  # and #write_exits! to mean that -- neither half is the whole rule, and a
  # reader who trusts one of them alone will be wrong.
  #
  # THIS HALF IS THE WAY IN: a name that RESOLVES to a PLACED ROOM of some other
  # place is refused, so an exterior exit never lands inside a building somebody
  # laid out. Three things go wrong at once without it, and only the first is
  # cosmetic: the party walks off a street straight into somebody's back room,
  # which is slice 4's decision to make and not a model's; the entry room's
  # spare exit -- the slot `Location::Interior` keeps free for the way IN -- is
  # spent on a door somewhere else; and a room already carrying its full
  # `Location::ExitsSchema::MAX_EXITS` takes one more, which
  # `EngineSweep::Invariants#exit_cap` fails a walk for. THE NAME IS DROPPED
  # WHOLE and no stub is created under it: a second location called what a room
  # is already called is the duplicate #find_location exists to prevent.
  #
  # THE OTHER HALF IS THE WAY OUT, AND THIS CHECK CANNOT MAKE IT. A name that
  # does NOT resolve becomes a stub, and `.create_stub!` writes no
  # `parent_location` at all -- every invented neighbour is born at the
  # outermost level, so nothing here could tell a door out of a room from a door
  # between two streets. What holds instead is #write_exits!, which asks for no
  # exits at all for a placed room of a laid-out interior: those rooms' doors
  # are `Location::Interior`'s, decided before anybody typed a line. For
  # everything else an outermost stub is the RIGHT neighbour -- an outermost
  # place opens onto an outermost place, and a street inside a district that
  # opens onto somewhere outside the district is a street you can leave the
  # district by.
  #
  # PLACEMENT, NOT `parent_location_id` EQUALITY, is what both halves are keyed
  # on, and `#known_location_names` says why at length: PLAIN CONTAINMENT -- a
  # `parent` with no box, which a world file may write -- is not an interior and
  # is not gated as one. Keyed on parent equality this would refuse a street
  # inside a district every outermost name it reused and leave it realized with
  # no way out.
  #
  # BOTH ENDS HAVE THE BUDGET, checked here rather than in #connect! because A
  # DOOR IS TWO ROWS and a per-direction check would write one of them -- the
  # first row spends this location's allowance, so the second call would find it
  # gone and leave a one-way door behind.
  # AND A NAME THAT RESOLVES TO A BUILDING SOMEBODY HAS ALREADY OPENED IS
  # RESOLVED ONE STEP FURTHER, to the room its way in lands on. The captain's
  # Call 5 of 2026-09-07 said as a rule about writing rather than as one about
  # repair: a model may name a place -- that is what a place is FOR -- and the
  # engine decides that naming a building means opening a door onto a room of
  # it. #open_the_way_in! is the same rule applied to the doorways a place
  # already had; this is it applied to the next one.
  #
  # AND `#room_elsewhere?` IS ASKED FIRST, OF THE NAME AS WRITTEN, which is what
  # keeps the two rules from cancelling each other out. That check refuses a
  # name that resolves to a PLACED ROOM of another building -- a room a model
  # chose -- and a place is not one, so a building passes it and is then
  # resolved. Resolving first would hand the check the entry room and it would
  # refuse the very door this paragraph exists to open.
  #
  # A PLACE NOBODY HAS OPENED RESOLVES TO ITSELF (`Location::Interior.way_in`),
  # because it has no rooms yet -- the doorway onto it is the way in, waiting,
  # and #open_the_way_in! moves it the moment there is somewhere for it to go.
  #
  # AND EVERY ONE OF THOSE GATES IS ASKED HERE AND NOWHERE ELSE, on the records
  # as they stand when this proposal is reached rather than as they stood when
  # the answer arrived. `#write_exits_serially!` says at length why nothing
  # predicts this method's verdict ahead of it.
  def connect_exit!(attributes, into_written: false)
    name = sanitize_string(attributes["name"])
    return if name.blank? || same_place_as_this_one?(name)

    existing = find_location(name)
    return if room_elsewhere?(existing)

    existing = Location::Interior.way_in(existing) if existing
    return if existing&.realized? && !into_written && !connected?(existing)
    return unless room_for_this_door?(existing)

    neighbour = existing || create_stub!(name, sanitize_string(attributes["teaser"]),
                                         inside: sanitize_string(attributes["inside"]),
                                         population: population(attributes))

    connect!(location, neighbour, attributes)
    connect!(neighbour, location, attributes)
  end

  # WHETHER THIS ROOM AND THE FAR SIDE CAN EACH TAKE ONE MORE WAY OUT. A
  # neighbour that does not exist yet is born with none, so only this room's
  # allowance is ever in question for it.
  #
  # AN EDGE THAT ALREADY EXISTS IS NOT A NEW DOOR and is never refused for
  # budget: naming a neighbour this room already reaches costs nothing
  # (#room_for_exits), and #connect! writes the missing row of a half-written
  # pair rather than a fifth way out.
  def room_for_this_door?(existing)
    return true if existing && connected?(existing)

    room_for_exits.positive? && (existing.nil? || existing.exits.count < Location::ExitsSchema::MAX_EXITS)
  end

  # `#rooms_elsewhere` ASKED OF ONE ROW: whether this is a placed room of a
  # place that is not the one this location is in. The query and this predicate
  # are one rule at two boundaries -- the query keeps the name off the prompt,
  # this keeps the door out of the records -- and only the second of them is
  # something nothing depends on a model for.
  def room_elsewhere?(other)
    return false if other.nil?

    other.placed? && other.parent_location_id.present? &&
      other.parent_location_id != location.parent_location_id
  end

  # THE ROW A MODEL'S NAME FOR A PLACE MEANS, or nil for a place this story has
  # never had -- and the whole of what stands between an exits answer and a
  # SECOND row for a place the world already holds.
  #
  # MATCHED THROUGH `WorldSeed.find_location`, WHICH IS THE MATCHER ALREADY IN
  # THE TREE. Not a second reading of "the same name written differently"
  # written here: `WorldSeed.natural_key` is the repo's one spelling of that
  # question, `Story::Doctor#duplicate_locations` groups on it, and a generator
  # that resolved a name the doctor calls one thing to two rows would write the
  # defect the doctor exists to report -- in the same request, from the same
  # answer. The delegation is the guarantee that those two cannot drift.
  #
  # THE DEFECT IT CLOSES, proved offline with no model call (the captain's Call
  # 7 of 2026-09-08). `Location::ExitsSchema` asks for a name of "1 to 4 words,
  # no article" while the prompt lists the world's places AS STORED, articles
  # and all. So a world holding `The Causeway Court` is correctly answered
  # `Causeway Court`, an exact lowercased match missed it, and `#connect_exit!`
  # created a duplicate stub -- sometimes with a footprint and a whole floor
  # plan hung off it. This is a RECORD-MATCHING fix and deliberately not a
  # prompt one: the schema's wording and the prompt's list are what the exits
  # lab exists to measure, and nothing here may depend on a model spelling a
  # name the way the database happens to.
  #
  # AND IT GOES NO WIDER THAN `.natural_key` GOES. Case, runs of whitespace and
  # a leading article are not part of a name; punctuation, possessives and
  # plurals still are, so two genuinely different places stay two places. That
  # boundary is argued in `.natural_key`'s own header and the argument is
  # sharper here than at a seed file, because this side WRITES: folding two
  # names too eagerly does not duplicate a room, it silently hands one room's
  # doorways to another and there is no repair for that.
  #
  # PASS 3 -- the place-and-box reading -- never runs from here, because it
  # needs a seed document and this caller has none. Every name an exits answer
  # can carry is settled by the two written-name passes.
  # THIS ROOM NAMING ITSELF, and it is asked on `WorldSeed.natural_key` for the
  # same reason #find_location is. A plain `casecmp?` here was safe only while
  # the matcher below was also exact: once a name without its article resolves,
  # a room called `The Causeway Court` answering `Causeway Court` would resolve
  # to ITSELF and #connect! would write a door from the room to the room. The
  # two questions are one question -- "is this the same place?" -- so they read
  # the same key, and widening one without the other trades a duplicate row for
  # a self-loop.
  def same_place_as_this_one?(name)
    WorldSeed.natural_key(name) == WorldSeed.natural_key(location.name.to_s)
  end

  def find_location(name)
    WorldSeed.find_location(story, name)
  end

  # A ROOM COMING INTO EXISTENCE, and the moment its danger is decided. The
  # captain's seventh ruling of 2026-09-04 evening: monster placement is a
  # rolled per-room parameter, *engine-rolled when the room is born*. A stub IS
  # a room being born -- it is created the moment a neighbour names it as an
  # exit, long before anybody walks in -- so the roll belongs here rather than
  # at realization, where it would depend on which order a player explored in.
  #
  # `Location::Danger.for_a_new_room` is the roll and it is seeded, so a world
  # regenerated from the same story at the same moment comes out the same way.
  # A SEEDED room is never rolled: `WorldSeed::Loader` writes what the file says
  # and an absent key is `Location::SAFE`, which is the rule every other seeded
  # parameter is under.
  # AND THE `inside` PICK IS WRITTEN HERE, AS A FOOTPRINT AND NOT AS A COLUMN OF
  # ITS OWN. `Location::Parameters::INSIDE` is the band each label names in paces
  # and the engine rolls both sides inside it, so `Location#place?` -- which is
  # `interior? && !placed?`, a footprint and no position -- starts answering true
  # for a generated stub with no new column and no new writer. That predicate's
  # own header said this is how it would happen and that it would not have to
  # move; this is the day, and it did not.
  #
  # ONLY A STUB BEING BORN, never a place that already exists: a footprint is a
  # world's parameter and this does not overrule one (`Location::Interior`'s
  # rule). `#connect_exit!` reaches here only when the name resolved to nothing.
  #
  # THE TWO FACTS AN ANSWER MAY CARRY ABOUT A PLACE IT IS NOT DESCRIBING ARE
  # SIMPLY HANDED ON -- `.create_stub!` is where a room being born is made, and
  # the footprint roll lives there so the lab and `Quest::Deadline` reach it
  # too. What is left here is why the exits call is the one asked.
  #
  # THE WORD FOR HOW POPULATED IT IS, IF THE ANSWER CARRIED ONE. The
  # captain's ruling of 2026-09-07 -- the narrator picks how populated a place is
  # from a closed list -- and this is the moment that pick is kept:
  # `Location::Population` needs the word before the room's OWN detail prompt is
  # built, and the only call with any reason to have an opinion about a place it
  # is not describing is the one naming the way there.
  #
  # IT IS A COLUMN WHERE `inside` IS A FOOTPRINT, and the difference is which
  # question the pick answers. A size can be spent immediately -- the engine rolls
  # paces and writes them, and nothing needs to remember the word. A population
  # word cannot: the count is rolled when somebody WALKS IN, which may be never,
  # so the word has to survive on the row until then.
  #
  # NOT VALIDATED HERE, and deliberately: `Location::Population.label_for` reads
  # the column and rolls a word for a row that has none, so a model that left the
  # field out or answered outside the enum leaves a stub the engine decides for.
  # `Location#population` refuses a word the table has no band for, which is the
  # verify half; sanitizing it to nil first would turn a wrong answer into a
  # failed save of the whole room.
  def create_stub!(name, teaser, inside: nil, population: nil)
    self.class.create_stub!(story, name: name, teaser: teaser, inside: inside, population: population)
  end

  # THE WORD THIS ANSWER PICKED FOR THAT PLACE, or nil for anything the table has
  # no band for. A word outside the enum is a model ignoring a closed list, and
  # nil is what the engine rolls for -- so an unrecognisable answer costs the
  # room its pick and nothing else. `Location::Population` is the one table and
  # this is the only reader of a model's answer to it.
  #
  # A WORD IS ONLY TAKEN FOR A ROOM BEING BORN. An exit naming a place that
  # already exists reaches `#connect_exit!`'s `existing` branch, and that row's
  # word is its own: a neighbour's guess must not overwrite what a seed file
  # wrote or what the room the player has already been in was born with. This is
  # `#create_stub!`'s argument for that reason and not an update.
  def population(attributes)
    word = sanitize_string(attributes["population"])

    word if Location::Population::BANDS.key?(word)
  end

  # Whether the player can already get between here and there, either way
  # round. Both rows are written together, so one direction is enough to know
  # the edge exists -- the second check is only so a half-written pair does not
  # read as a new door.
  def connected?(neighbour)
    LocationConnection.exists?(location: location, connected_location: neighbour) ||
      LocationConnection.exists?(location: neighbour, connected_location: location)
  end

  # Connections are directional rows, so both directions are written: the
  # player has to be able to walk back the way they came, and the return trip
  # exists before the far side is ever realized. Both rows carry the same
  # values, which is only correct because LocationConnection's enums are
  # direction-neutral; `time_to_travel` is derived there, not copied here.
  #
  # AND THIS IS WHERE A PROPOSED LABEL IS JUDGED, because it is where a row is
  # created. A pair that already exists returns above and its labels are never
  # read at all, so a name the model spent on a door this room already has
  # cannot fail anything. A row that IS being written and does not validate
  # raises `UnusableExitLabel` -- the one failure #write_exits_serially! will
  # not keep a paid answer through. Anything the save itself raises is left as
  # itself: a uniqueness collision written by the far side's own generator is
  # not a bad label and does not cost this room its answer.
  def connect!(from, to, attributes)
    return if LocationConnection.exists?(location: from, connected_location: to)

    edge = LocationConnection.new(
      location: from,
      connected_location: to,
      distance: sanitize_string(attributes["distance"]),
      travel_method: sanitize_string(attributes["travel_method"])
    )
    raise UnusableExitLabel.new(edge) unless edge.valid?

    edge.save!
  end
end
