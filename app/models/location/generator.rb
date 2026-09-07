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
  def self.create_stub!(story, name:, teaser:)
    story.locations.create!(name: name, teaser: teaser, detail_level: :stub,
                            danger: Location::Danger.for_a_new_room(story))
  end

  # Description and lore, then the stub exits leading out -- saved in that
  # order. The description used to be held unsaved until the exits call
  # returned, so an exits failure threw away the more expensive of the two
  # calls along with the cheaper one.
  #
  # A failure after the description lands leaves a realized room with no way
  # out. `realize!` returns an already-realized location untouched, which is
  # the "generate once per place" guarantee, so recovering from that means
  # calling #write_exits! directly rather than realizing the room again.
  #
  # THE INSIDE OF A PLACE IS LAID OUT INSIDE #write_detail! rather than on a
  # third line here, and #lay_out_interior!'s header is where the reason lives:
  # it has to happen on the near side of the flip to `realized`, and that flip
  # is #write_detail!'s to make.
  def realize!
    return location if location.realized?

    write_detail!
    write_exits!

    location
  end

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
  # BEFORE THE FLIP TO `realized`, AND IN THE SAME TRANSACTION AS IT. The flip
  # is the "generate once per place" guarantee -- `#realize!` returns a realized
  # location untouched -- so a layout that raised on the far side of it would
  # leave a place realized for ever carrying a footprint and no inside, with
  # nothing to retry it and nothing that even looks at it again. Written and
  # rolled back together, a layout that raises leaves the stub exactly as it
  # was, and the next entry lays it out. `Story::Doctor`'s
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
  def detail_schema = location.place? ? Location::PlaceSchema : Location::DetailSchema

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
    detail = ask(detail_schema, detail_prompt)

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

    # THE ROW, THEN THE INSIDE, THEN THE FLIP -- one transaction and that order.
    # A room is a child of a saved place, so this location has to exist before
    # `Location::Interior` can put anything in it (`#lay_out_interior!` may be
    # handed a stub that was never saved); and the flip comes last because it is
    # what makes this place one nobody realizes again.
    Location.transaction do
      location.save!
      lay_out_interior!(detail["parameters"])
      location.update!(detail_level: :realized)
    end

    # AND A BUILDING KEEPS NEITHER, which is the verify half of the sentence
    # `#place_prompt` says and `Location::PlaceSchema` has no field for. Nobody
    # stands in a container (`Location::Interior.way_in`), so a thing admitted
    # into one is a thing no player can ever pick up and a person is somebody
    # nobody can talk to -- and an answer carrying either is an answer the
    # engine drops rather than a state it writes. The rooms are where both
    # belong, and each is asked as it is reached.
    return location if location.laid_out?

    registry.admit!(detail["items"])
    # AND WHO IS IN IT, on the captain's ruling that *rooms should be born with
    # people in them sometimes.* The same shape as the line above it and for the
    # same reasons: structured records out of the call that describes the room,
    # never a narrator tool and never a scan of prose. `Character::Registry`
    # decides -- it refuses a taken name, it refuses past the room's cap and the
    # world's, and it never moves somebody who already stands somewhere.
    cast_registry.admit!(detail["people"])

    location
  end

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
    @cast_registry ||= Character::Registry.new(location)
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
    return location if interior_room? || location.laid_out?

    # ALREADY FULL, so there is nothing to ask and nothing to spend. A stub can
    # arrive at the cap before anybody walks into it: a world file seeds edges,
    # and every neighbour that named this place on its way to being realized
    # wrote one. See Location::ExitsSchema::MAX_EXITS.
    return location if room_for_exits.zero?

    exits = Array(ask(Location::ExitsSchema, exits_prompt)["exits"])

    Location.transaction do
      exits.each { |attributes| connect_exit!(attributes) if room_for_exits.positive? }
      exits.each { |attributes| connect_exit!(attributes, into_written: true) } unless location.exits.exists?
    end

    location
  end

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
    @agent ||= BaseAgent.new(purpose: "location", playthrough: @playthrough).with_instructions(system_prompt)
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
  # is what keeps this cheap: how many people it may name at all, and WHO THEY
  # ALREADY ARE. Race, age and sex are rolled by `Character::Registry#slots`
  # before this prompt is built and stated here per slot, so the model writes a
  # person the engine has already decided rather than deciding one -- the rule
  # `Character::Generator` states as *asking for a value the prompt just
  # supplied is a decision bought twice.*
  #
  # NOBODY IS THE ORDINARY ANSWER and the sentence says so twice, because a room
  # with somebody in it is a room with a conversation in it and most rooms are
  # not that. A world at its cap is asked for nobody at all, and the schema's
  # array can honestly come back empty.
  def people_instructions
    allowance = cast_registry.allowance

    return "Do not list any people: there is nobody left for this world to hold." if allowance.zero?

    <<~PROMPT.rstrip
      ## Who Is Here
      List AT MOST #{allowance} #{"person".pluralize(allowance)} who #{allowance == 1 ? "is" : "are"} in this place right now.
      - NOBODY is the right answer for most rooms, and an empty list is a complete
        answer. Name somebody only when this place would be strange without them
      - Anyone you name is somebody the player can walk up to and talk to, so they
        have to have a reason to be standing here and something they want
      - Do not write the player, and do not write somebody passing through
      - Never give them the name of a place, of a thing, or any name already
        spoken for above

      #{slot_details(allowance)}
    PROMPT
  end

  # The people the engine has already decided on, one line each, in the order
  # the answer's entries are read back in.
  def slot_details(allowance)
    lines = cast_registry.slots.first(allowance).each_with_index.map do |details, index|
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
      - Respect the stated length of each field
    PROMPT
  end

  private

  def ask(schema, prompt)
    agent.with_schema(schema).ask(prompt).content
  end

  def story_context
    <<~CONTEXT
      ## Universe Details
      #{story.universe.prompt_details(:place)}

      ## Story Details
      title: #{story.title}
      genre: #{story.genre}
      preface: #{story.preface}
      summary: #{story.summary}
    CONTEXT
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
  def connect_exit!(attributes, into_written: false)
    name = sanitize_string(attributes["name"])
    return if name.blank? || name.casecmp?(location.name.to_s)

    existing = find_location(name)
    return if room_elsewhere?(existing)

    existing = Location::Interior.way_in(existing) if existing
    return if existing&.realized? && !into_written && !connected?(existing)
    return unless room_for_this_door?(existing)

    neighbour = existing || create_stub!(name, sanitize_string(attributes["teaser"]),
                                         inside: sanitize_string(attributes["inside"]))

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

  def find_location(name)
    story.locations.where("LOWER(name) = ?", name.downcase).first
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
  # SEEDED ON THE ROW'S OWN ID, on its OWN AXIS. `Roll::FOOTPRINT` rather than
  # `INTERIOR`'s: the footprint is drawn before the layout and decides what the
  # layout has to divide, so drawing both from one seed would be one roll
  # deciding twice. See `Roll`'s header for what an axis buys.
  def create_stub!(name, teaser, inside: nil)
    room = self.class.create_stub!(story, name: name, teaser: teaser)
    sides = Location::Parameters.from("inside" => inside).footprint(footprint_rng(room))
    room.update!(width: sides.first, depth: sides.last) if sides

    room
  end

  def footprint_rng(room) = Roll.generator(story: story.id, sequence: room.id, kind: Roll::FOOTPRINT)

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
  def connect!(from, to, attributes)
    return if LocationConnection.exists?(location: from, connected_location: to)

    LocationConnection.create!(
      location: from,
      connected_location: to,
      distance: sanitize_string(attributes["distance"]),
      travel_method: sanitize_string(attributes["travel_method"])
    )
  end
end
