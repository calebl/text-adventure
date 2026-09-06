# Realizes a location: fills in the description and lore the player reads, then
# creates the stub locations the exits lead to. Those stubs are the whole point
# -- when the narrator says three doors lead out, all three have to be real
# records before the player picks one, but only the one they walk through is
# ever written in full.
#
# Generation happens once per place. A realized location is returned untouched,
# which is what makes walking back into a room give you the room you left.
#
# THE THREE PROMPT BLOCKS BELOW HAVE A BENCH: `#people_instructions`,
# `#items_instructions` and `#exits_prompt` are what `rake eval:realization`
# measures, by staging a fixed stub and scoring the answer against the records
# it was built from. Do not edit one of them without a stored baseline to judge
# the change against -- EVALUATION.md -> The realization bench is the protocol
# and `Eval::Realization` is the instrument.
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
  # neither OFFERED (`#known_location_names` lists only locations at this one's
  # own containment level) nor ACCEPTED (`#connect_exit!` refuses a row inside
  # another place outright), whenever the rooms happen to have been written. A
  # rule about who may be a neighbour holds in an order a rule about which call
  # comes first does not.
  #
  # THE ROOMS ARE NOT WIRED TO THIS PLACE'S OWN EXITS, so the party still stands
  # in the place rather than in one of its rooms. Entering a room instead of the
  # building it is in is slice 4's, and the layout has to exist before anything
  # can send anybody into it.
  #
  # AN ALREADY-REALIZED PLACE IS NEVER LAID OUT, because `#realize!` returns one
  # untouched -- the "generate once per place" guarantee, which this is downhill
  # of rather than an exception to. So a world file that ships a place already
  # written out is a world whose author is laying its inside out themselves, and
  # `test/fixtures/files/a-world-with-an-interior.yml` is exactly that.
  def lay_out_interior!
    return location unless location.place?

    Location::Interior.lay_out!(location)

    location
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
    detail = ask(Location::DetailSchema, detail_prompt)

    location.description = sanitize_string(detail["description"])
    location.lore = sanitize_string(detail["lore"])

    # THE ROW, THEN THE INSIDE, THEN THE FLIP -- one transaction and that order.
    # A room is a child of a saved place, so this location has to exist before
    # `Location::Interior` can put anything in it (`#lay_out_interior!` may be
    # handed a stub that was never saved); and the flip comes last because it is
    # what makes this place one nobody realizes again.
    Location.transaction do
      location.save!
      lay_out_interior!
      location.update!(detail_level: :realized)
    end

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
  def write_exits!
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

  def detail_prompt
    <<~PROMPT
      #{story_context}

      ## The Place
      name: #{location.name}
      teaser: #{location.teaser}

      ## Instructions
      Write this place out in full.
      - The description is what the player reads on arrival. Address them as "you"
      - Describe what is here now, not the history -- the history is the lore
      - Stay consistent with the universe and with the teaser above
      - Respect the stated length of each field

      #{items_instructions}

      #{people_instructions}
    PROMPT
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

  # A ROOM INSIDE ANOTHER PLACE IS NOT ON THE LIST. Only locations at this one's
  # own containment level are, which is the half of the rule that costs a
  # sentence -- the half nothing depends on the model for is #connect_exit!'s
  # refusal.
  #
  # THIS IS NOT A PROMPT CHANGE WANTING A STORED BASELINE, and it is worth
  # saying so here so nobody later reads it as one. Nothing wrote a
  # `parent_location` until `Location::Interior` did, so for every story any
  # baseline in `db/eval/` was measured on, every location in the story is at
  # the outermost level and this filter selects all of them. It RESTORES the
  # text those baselines were measured against rather than moving it.
  def known_location_names
    story.locations.where(parent_location_id: location.parent_location_id).where.not(id: location.id)
         .order(:id).map { |place| known_location_line(place) }.join("\n")
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
  # A DOOR NEVER CROSSES THE WALL OF A BUILDING. A neighbour has to sit at this
  # location's own containment level, so a name that resolves to a room inside
  # some place is refused outright and on every pass. Three things go wrong at
  # once without it, and only the first is cosmetic: the party walks off a
  # street straight into somebody's back room, which is slice 4's decision to
  # make and not a model's; the entry room's spare exit -- the slot
  # `Location::Interior` keeps free for the way IN -- is spent on a door
  # somewhere else; and a room already carrying its full `Location::ExitsSchema::MAX_EXITS`
  # takes one more, which `EngineSweep::Invariants#exit_cap` fails a walk for.
  # THE NAME IS DROPPED WHOLE and no stub is created under it: a second
  # location called what a room is already called is the duplicate #find_location
  # exists to prevent.
  #
  # BOTH ENDS HAVE THE BUDGET, checked here rather than in #connect! because A
  # DOOR IS TWO ROWS and a per-direction check would write one of them -- the
  # first row spends this location's allowance, so the second call would find it
  # gone and leave a one-way door behind.
  def connect_exit!(attributes, into_written: false)
    name = sanitize_string(attributes["name"])
    return if name.blank? || name.casecmp?(location.name.to_s)

    existing = find_location(name)
    return if existing && existing.parent_location_id != location.parent_location_id
    return if existing&.realized? && !into_written && !connected?(existing)
    return unless room_for_this_door?(existing)

    neighbour = existing || create_stub!(name, sanitize_string(attributes["teaser"]))

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
  def create_stub!(name, teaser) = self.class.create_stub!(story, name: name, teaser: teaser)

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
