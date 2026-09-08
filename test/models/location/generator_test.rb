require "test_helper"

class Location::GeneratorTest < ActiveSupport::TestCase
  OPENING = {
    "name" => "The Drowned Ledger",
    "teaser" => "A counting house with the tide coming in."
  }.freeze

  DETAIL = {
    "description" => "Water laps at the third stair and the ledgers are floating.",
    "lore" => "The house has collected debts here for two hundred years."
  }.freeze

  # The same answer with the room furnished. `items` rides on the detail call
  # (Location::DetailSchema), so this is one response and not a third one.
  FURNISHED = DETAIL.merge(
    "items" => [
      { "name" => "floating ledger", "description" => "A ledger swollen with water, still legible." },
      { "name" => "brass tide key", "description" => "A key on a wet cord, cut for a lock further down." }
    ]
  ).freeze

  # One person in the room, as `Location::DetailSchema`'s `people` array answers
  # with them: the sheet a `Character` is validated on, and nothing the engine
  # decides for itself (race, age and sex are `Character::Registry#slots`').
  PERSON = {
    "fullname" => "Maren Vosk", "nickname" => "Maren",
    "appearance" => "Waist-deep, sleeves pinned, counting something under her breath.",
    "personality" => "Brisk with strangers and slower to stop working than to answer.",
    "backstory" => "Maren Vosk was sent to close this house's books and stayed when the water came in.",
    "likes" => "A column that adds up, dry paper",
    "dislikes" => "Being asked twice, standing water",
    "fears" => "A debt nobody can prove"
  }.freeze

  # The same answer with somebody in the room. `people` rides on the detail call
  # exactly as `items` does, so this is still one response and not a third.
  PEOPLED = DETAIL.merge("people" => [ PERSON ]).freeze

  EXITS = {
    "exits" => [
      {
        "name" => "The Pump Gallery",
        "teaser" => "Something down there is still turning.",
        "distance" => "across the district",
        "travel_method" => "swimming",
        # HOW POPULATED THE PLACE THAT WAY IS, which is the pick the exits call
        # answers per exit and `.create_stub!` writes on the stub
        # (`Location::Population`). One word here and none on the second exit,
        # because a model that leaves it out is a case the engine has to survive:
        # the stub is written with no word and the engine rolls one.
        "population" => "a crowd"
      },
      {
        "name" => "Tidewater Stair",
        "teaser" => "Steps that go up out of the water.",
        "distance" => "adjacent",
        "travel_method" => "climbing"
      }
    ]
  }.freeze

  # A place with one way out. The schema allows it, and a room realized from a
  # neighbour already has its way back, so this is a whole answer.
  ONE_EXIT = { "exits" => [ EXITS["exits"].last ] }.freeze

  # A model answering with the whole of `max_items`, which is the case the
  # room's own cap has to survive: four named on top of whatever the room
  # already had.
  FOUR_EXITS = {
    "exits" => (1..4).map do |n|
      { "name" => "Named Way #{n}", "teaser" => "Something is that way.",
        "distance" => "adjacent", "travel_method" => "walking" }
    end
  }.freeze

  def setup
    @story = create(:story)
  end

  def realize(location, agent)
    BaseAgent.stub(:new, agent) do
      Location::Generator.new(location).realize!
    end
  end

  def stub_location(**attributes)
    create(:location, :stub, story: @story, **attributes)
  end

  # A ROOM OF A LAID-OUT BUILDING AND A ROOM IT REALLY HAS A DOOR TO, off
  # `Location::Interior`'s own output rather than placed by hand -- so a test of
  # what a room is TOLD stands on a floor plan the engine wrote. The pair is the
  # first room and the first neighbour the layout gave it, which the serpentine
  # guarantees exists for any building with more than one room in it.
  def laid_out_pair
    place = stub_location(name: "The Rusted Anchor", width: 12, depth: 8)
    Location::Interior.lay_out!(place)
    room = Location::Interior.entry_room(place.reload)

    [ room, room.exits.find { |far| far.box && room.box.wall_towards(far.box) } ]
  end

  # An edge this room already has before anybody asks for its exits: what a
  # world file seeds, and what a neighbour writes when it names this place.
  # Both directions, because that is how every edge in the app is written.
  def already_reaching(location, name)
    neighbour = create(:location, :stub, story: @story, name: name)
    create(:location_connection, location: location, connected_location: neighbour)
    create(:location_connection, location: neighbour, connected_location: location)
    neighbour
  end

  # --- the seam an interior is laid out through -------------------------------
  #
  # ON FIRST ENTRY TO A PLACE, which is what realizing a stub IS. See
  # `Location::Generator#lay_out_interior!` and `Location#place?`.

  test "realizing a stub that carries a footprint lays out its inside" do
    place = stub_location(name: "The Rusted Anchor", width: 12, depth: 8)

    realize(place, FakeAgent.new(DETAIL, ONE_EXIT))

    rooms = place.reload.child_locations
    assert_predicate rooms.count, :positive?
    assert(rooms.all?(&:placed?))
    assert(rooms.all?(&:stub?))
  end

  # THE ONE THAT MUST NOT FIRE. Every stub in every generated world carries no
  # extent, so realizing one has to write exactly what it wrote before this
  # seam existed.
  test "realizing an ordinary stub lays out nothing at all" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, EXITS))

    assert_empty location.reload.child_locations
    assert(location.exits.none?(&:placed?))
  end

  # --- stage one: the picks a model makes about a place -----------------------
  #
  # THE CAPTAIN'S CALL 2 of 2026-09-07: the exits call decides inside-or-not at
  # stub time, the detail call picks the rest at first entry. See
  # `Location::Parameters`.

  def exit_named(name, inside: nil)
    { "exits" => [ { "name" => name, "teaser" => "Something is that way.",
                     "distance" => "adjacent", "travel_method" => "walking" }.merge(
                     inside ? { "inside" => inside } : {}) ] }
  end

  test "an exit given an inside is born a place with a footprint" do
    here = stub_location(name: "The Harbour Road")

    realize(here, FakeAgent.new(DETAIL, exit_named("The Rusted Anchor", inside: "a few rooms")))

    anchor = Location.find_by(story: @story, name: "The Rusted Anchor")
    assert_predicate anchor, :place?, "Location#place? is the whole of the decision, and it answers true"
    assert_includes Location::Parameters::INSIDE.fetch("a few rooms"), anchor.width
    assert_includes Location::Parameters::INSIDE.fetch("a few rooms"), anchor.depth
    assert_empty anchor.child_locations, "the inside is laid out on first entry and not at stub time"
  end

  # THE FOOTPRINT IS ROLLED BY THE CLASS METHOD, which is where a room being born
  # is made -- so every caller that has a band gets an extent from it and no
  # caller has to remember the roll. `Lab::Realization::Runner` is the second
  # such caller and reaches it here rather than spelling the draw a second time.
  test "the class method rolls the footprint from the band, and none without one" do
    inside = Location::Generator.create_stub!(@story, name: "The Rope Walk", teaser: "A long shed.",
                                                      inside: "a warren of rooms")

    assert_predicate inside, :place?
    assert_includes Location::Parameters::INSIDE.fetch("a warren of rooms"), inside.width
    assert_includes Location::Parameters::INSIDE.fetch("a warren of rooms"), inside.depth

    flat = Location::Generator.create_stub!(@story, name: "The Tow Path", teaser: "Mud and rope.")

    assert_nil flat.width
    assert_nil flat.depth
    assert_not_predicate flat, :place?
  end

  # THE ONE THAT MUST NOT FIRE: a road, a shore, a clearing. And an answer with
  # no pick at all, which is a legal answer and the commonest one.
  test "an exit given no inside, or none at all, is born with no footprint" do
    [ "no inside", nil ].each_with_index do |pick, number|
      here = stub_location(name: "Road #{number}")

      realize(here, FakeAgent.new(DETAIL, exit_named("Open Ground #{number}", inside: pick)))

      assert_not_predicate Location.find_by(story: @story, name: "Open Ground #{number}"), :place?
    end
  end

  # A FOOTPRINT IS A WORLD'S PARAMETER AND THIS DOES NOT OVERRULE ONE.
  test "an exit that names a place that already exists does not resize it" do
    anchor = stub_location(name: "The Rusted Anchor", width: 12, depth: 8)
    here = stub_location(name: "The Harbour Road")

    realize(here, FakeAgent.new(DETAIL, exit_named("The Rusted Anchor", inside: "a warren of rooms")))

    assert_equal [ 12, 8 ], [ anchor.reload.width, anchor.depth ]
  end

  # RE-DERIVABLE FROM THE STORY AND THE ROW, on its own axis. The seed is plain
  # integer arithmetic over `Roll::FOOTPRINT`, so the same building comes out the
  # same size in any process for ever -- `Roll`'s standing rule, and the reason
  # the axis is not `INTERIOR`'s is that the footprint decides what the layout
  # has to divide.
  test "the footprint a stub was born with is the one its own seed re-derives" do
    here = stub_location(name: "The Harbour Road")

    realize(here, FakeAgent.new(DETAIL, exit_named("The Rusted Anchor", inside: "a warren of rooms")))

    anchor = Location.find_by(story: @story, name: "The Rusted Anchor")
    rng = Roll.generator(story: @story.id, sequence: anchor.id, kind: Roll::FOOTPRINT)

    assert_equal [ anchor.width, anchor.depth ],
                 Location::Parameters.from("inside" => "a warren of rooms").footprint(rng)
  end

  # THE OTHER HALF: the picks that decide what the engine builds inside, on the
  # detail call of the building itself.
  test "a place is asked the parameters block and a room is not" do
    place = stub_location(name: "The Rusted Anchor", width: 12, depth: 8)
    room = stub_location(name: "The Harbour Road")

    assert_equal Location::PlaceSchema, Location::Generator.new(place).detail_schema

    # A ROOM'S SCHEMA IS A SHAPE OF `Location::DetailSchema` AND NOT ALWAYS THE
    # CLASS ITSELF, since the 2026-09-07 population ruling: `.for_people` builds
    # a variant requiring exactly the rolled count, and every shape answers to
    # this name (`Location::DetailSchema`). What matters here is that a room is
    # never sent the `parameters` block, which is what the name says.
    assert_equal "Location::DetailSchema", Location::Generator.new(room).detail_schema.name
    assert_not_includes Location::Generator.new(room).detail_schema.properties.keys, :parameters
  end

  test "the picks a building came back with are what its inside is laid out from" do
    place = stub_location(name: "Blackfang Warren", width: 15, depth: 11)
    picks = DETAIL.merge("parameters" => { "storeys_above" => "ground floor only",
                                           "storeys_below" => "two levels down",
                                           "danger" => "dangerous",
                                           "gradient" => "worse the deeper you go",
                                           "hazard" => "airless" })

    realize(place, FakeAgent.new(picks))

    rooms = place.reload.child_locations.to_a
    assert_equal (-2..0).to_a, rooms.map(&:z).uniq.sort, "the storeys are the picks, read back off the rows"
    assert(rooms.select(&:hazard).all? { |room| room.hazard == "airless" })
    assert(rooms.all? { |room| Location::DANGERS.key?(room.danger) })
  end

  # A BUILDING IS ASKED FOR NOBODY AND NOTHING, because the rooms are where a
  # person stands and a thing lies. The schema has no field for either, so an
  # answer carrying one is an answer nothing reads.
  test "a building writes no people and no things into itself" do
    place = stub_location(name: "The Rusted Anchor", width: 12, depth: 8)
    smuggled = DETAIL.merge("items" => [ { "name" => "brass key", "description" => "A key." } ],
                            "people" => [ PERSON ])

    realize(place, FakeAgent.new(smuggled))

    assert_empty place.reload.items
    assert_empty Character.present_in(place)
  end

  # --- the way in ------------------------------------------------------------
  #
  # THE CAPTAIN'S CALL 5, 2026-09-07: the neighbour's doorway lands on the entry
  # room, and the place row is never an endpoint. See
  # `Location::Generator#open_the_way_in!`.

  test "realizing a place moves the doorway it arrived with onto its entry room" do
    place = stub_location(name: "The Rusted Anchor", width: 12, depth: 8)
    road = already_reaching(place, "The Harbour Road")

    realize(place, FakeAgent.new(DETAIL))

    entry = Location::Interior.entry_room(place.reload)
    assert_empty place.exits, "a place is never the far end of a doorway once it has an inside"
    assert_includes entry.exits, road
    assert_includes road.reload.exits, entry
  end

  # AN EXTERIOR EDGE KEEPS ITS LABEL -- `Location::Interior`'s two travel-time
  # rules. There is no geometry between a road and a counting room to derive one
  # from, so the label a model picked for the way to the building is the label
  # of the way to its entry room, in both directions.
  test "the way in keeps the distance and the travel method it was written with" do
    place = stub_location(name: "The Rusted Anchor", width: 12, depth: 8)
    road = create(:location, :stub, story: @story, name: "The Harbour Road")
    create(:location_connection, location: place, connected_location: road,
                                 distance: "across the district", travel_method: "climbing")
    create(:location_connection, location: road, connected_location: place,
                                 distance: "across the district", travel_method: "climbing")

    realize(place, FakeAgent.new(DETAIL))

    edge = LocationConnection.find_by(location: Location::Interior.entry_room(place.reload), connected_location: road)
    assert_equal "across the district", edge.distance
    assert_equal "climbing", edge.travel_method
  end

  # A PLACE WITH AN INSIDE IS ASKED FOR NO WAYS OUT, and a fake with one queued
  # answer is what proves the call was never made: a second ask raises.
  test "a place that has been laid out is asked for no ways out of its own" do
    place = stub_location(name: "The Rusted Anchor", width: 12, depth: 8)
    agent = FakeAgent.new(DETAIL)

    realize(place, agent)

    assert_equal 1, agent.prompts.size, "the exits call was bought for a building nobody stands in"
  end

  # A PLACE CAN BE NAMED BY MORE THAN ONE NEIGHBOUR BEFORE ANYBODY OPENS IT, and
  # the layout keeps exactly one slot free -- so the rest land on the ground
  # floor beside the entry room (`Location::Interior.doorstep`).
  test "a second doorway lands on a room of the ground floor" do
    place = stub_location(name: "The Rusted Anchor", width: 12, depth: 8)
    roads = [ already_reaching(place, "The Harbour Road"), already_reaching(place, "Anchor Lane") ]

    realize(place, FakeAgent.new(DETAIL))

    landed = roads.map { |road| road.reload.exits.sole }
    assert_empty place.reload.exits
    assert(landed.all? { |room| room.parent_location_id == place.id }, "every way in lands inside the building")
    assert(landed.all? { |room| room.z.zero? }, "a street door opens onto the ground floor")
  end

  # AND A DOORWAY WITH NOWHERE LEFT TO LAND IS DROPPED rather than left on the
  # container, which is the one shape the whole method exists to make
  # impossible. A place too small to divide has one room to a storey, so its
  # doorstep is one room and the stairs have already spent most of its cap --
  # which is exactly the state where a way in has nowhere to go.
  test "a doorway with no room left to land in is dropped rather than left on the place" do
    place = stub_location(name: "The Watch Box", width: 3, depth: 3)
    roads = (1..Location::ExitsSchema::MAX_EXITS + 1).map { |n| already_reaching(place, "Lane #{n}") }

    realize(place, FakeAgent.new(DETAIL))

    landed, dropped = roads.partition { |road| road.reload.exits.any? }

    assert_empty place.reload.exits, "a dropped doorway is dropped, not left on the container"
    assert_predicate dropped, :any?, "the fixture wants more ways in than this building has room for"
    assert(landed.all? { |road| road.exits.sole.parent_location_id == place.id })
    assert(place.child_locations.all? { |room| room.exits.count <= Location::ExitsSchema::MAX_EXITS },
           "no room leads more ways out than its cap, whatever the way in wanted")
  end

  # THE OTHER HALF OF THE SAME RULE: a model may name a building, and the engine
  # decides that naming one means opening a door onto a room of it.
  test "an exit that names a building already opened lands on its entry room" do
    place = stub_location(name: "The Rusted Anchor", width: 12, depth: 8)
    realize(place, FakeAgent.new(DETAIL))
    entry = Location::Interior.entry_room(place.reload)

    road = stub_location(name: "The Harbour Road")
    named = { "exits" => [ { "name" => "The Rusted Anchor", "teaser" => "Shutters down.",
                             "distance" => "adjacent", "travel_method" => "walking" } ] }
    realize(road, FakeAgent.new(DETAIL, named))

    assert_includes road.reload.exits, entry
    assert_empty place.reload.exits
    assert_nil Location.find_by(story: @story, name: "The Rusted Anchor")&.exits&.first
  end

  # AND A PLACE NOBODY HAS OPENED IS STILL NAMEABLE AS ITSELF. It has no rooms
  # to land on; the doorway onto it is the way in, waiting, and it is moved the
  # moment somebody walks through it.
  test "an exit that names a building nobody has opened lands on the building" do
    place = stub_location(name: "The Rusted Anchor", width: 12, depth: 8)
    road = stub_location(name: "The Harbour Road")
    named = { "exits" => [ { "name" => "The Rusted Anchor", "teaser" => "Shutters down.",
                             "distance" => "adjacent", "travel_method" => "walking" } ] }

    realize(road, FakeAgent.new(DETAIL, named))

    assert_includes road.reload.exits, place
  end

  # LAID OUT ONCE, EVER, which is `#realize!`'s own guarantee said about
  # geometry: walking back in gives you the building you left.
  test "a place that already has rooms is not laid out a second time" do
    place = stub_location(name: "The Rusted Anchor", width: 12, depth: 8)
    Location::Interior.lay_out!(place)
    before = place.child_locations.order(:id).pluck(:id)

    realize(place, FakeAgent.new(DETAIL, ONE_EXIT))

    assert_equal before, place.reload.child_locations.order(:id).pluck(:id)
  end

  # A DOOR NEVER CROSSES THE WALL OF A BUILDING. The rooms of a laid-out place
  # are stubs in the same story as every other location, so nothing but this
  # refusal stops the exits call reusing one by name -- and an exterior edge
  # into a room walks the party off the street into somebody's back room, spends
  # the entry room's reserved slot, and can take a room past
  # `Location::ExitsSchema::MAX_EXITS`.
  test "an exit that names a room inside another place is refused" do
    place = stub_location(name: "The Rusted Anchor", width: 12, depth: 8)
    realize(place, FakeAgent.new(DETAIL, ONE_EXIT))
    room = place.reload.child_locations.order(:id).last
    named_room = { "exits" => [ { "name" => room.name, "teaser" => "A door that should be locked.",
                                  "distance" => "adjacent", "travel_method" => "walking" } ] }
    road = stub_location(name: "The Harbour Road")

    realize(road, FakeAgent.new(DETAIL, named_room))

    assert_empty road.reload.exits
    assert_empty room.reload.exits.where(parent_location_id: nil)
    assert_equal 1, @story.locations.where(name: room.name).count
    assert(place.reload.child_locations.all? { |one| one.exits.count <= Location::ExitsSchema::MAX_EXITS })
  end

  # AND THE FLOOR DOES NOT LIFT IT. `#write_exits!` takes a written room rather
  # than sealing a player in; a room inside a building is a name it cannot
  # honour on any pass, because honouring it breaks an invariant.
  test "the fewer-exits floor does not open a door into a room either" do
    place = stub_location(name: "The Rusted Anchor", width: 12, depth: 8)
    realize(place, FakeAgent.new(DETAIL, ONE_EXIT))
    room = place.reload.child_locations.order(:id).first
    named_room = { "exits" => [ { "name" => room.name, "teaser" => "A door that should be locked.",
                                  "distance" => "adjacent", "travel_method" => "walking" } ] }
    road = stub_location(name: "The Harbour Road")

    realize(road, FakeAgent.new(DETAIL, named_room))

    assert_empty road.reload.exits
    assert_empty room.reload.exits.where(parent_location_id: nil)
  end

  # AN INTERIOR ROOM'S WAYS OUT ARE THE ENGINE'S. `Location::Interior` wrote
  # every door and every stair the room has, under guarantees a model cannot be
  # held to, so realizing the room writes its prose and does not ask for exits
  # at all -- neither a sibling's name nor an invented one is honoured, and the
  # entry room's reserved slot is left where it is.
  test "realizing a room inside a place honours no exit a model names" do
    place = stub_location(name: "The Rusted Anchor", width: 12, depth: 8)
    realize(place, FakeAgent.new(DETAIL, ONE_EXIT))
    rooms = place.reload.child_locations.order(:id).to_a
    room = rooms.first
    named = { "exits" => [
      { "name" => rooms.last.name, "teaser" => "The next room along.",
        "distance" => "adjacent", "travel_method" => "walking" },
      { "name" => "The Strongroom", "teaser" => "A door that should have been locked.",
        "distance" => "adjacent", "travel_method" => "walking" }
    ] }
    edges = LocationConnection.count
    locations = @story.locations.count
    agent = FakeAgent.new(DETAIL, named)

    BaseAgent.stub(:new, agent) { Location::Generator.new(room).realize! }

    assert_predicate room.reload, :realized?
    assert_equal edges, LocationConnection.count
    assert_equal locations, @story.locations.count
    assert_nil @story.locations.find_by(name: "The Strongroom")
    assert_not_includes agent.schemas, Location::ExitsSchema
  end

  # --- and what it IS told instead --------------------------------------------
  #
  # THE ROOM'S OWN FLOOR PLAN, AS FACTS. The captain's first ruling of
  # 2026-09-06 has the interior laid out before anybody walks in, so by the time
  # a model is asked to write one of its rooms the size, the storey and every
  # door are already decided -- `Location::Plan` is the one author of them and
  # this is the seam it reaches the prompt through.

  test "a room inside a place is told its own size, storey and doors" do
    room, sibling = laid_out_pair
    agent = FakeAgent.new(DETAIL)

    BaseAgent.stub(:new, agent) { Location::Generator.new(room).realize! }

    prompt = agent.prompts.sole
    assert_includes prompt, "## Where This Room Is"
    assert_includes prompt, "This room is #{room.box.width} by #{room.box.depth} paces"
    assert_includes prompt, "It is on storey #{room.box.z} of The Rusted Anchor"
    assert_includes prompt, "a door in the #{room.box.wall_towards(sibling.box)} wall, to #{sibling.name}"
    assert_includes prompt, "Those are every way out of this room"
  end

  # THE FACTS ARE THE PLAN'S AND ARE NOT ASSEMBLED HERE, so the room writer and
  # the narrator cannot come to describe one building two ways
  # (`Playthrough::Moment#narration_context`).
  test "what the room is told is what Location::Plan says, word for word" do
    room, = laid_out_pair
    agent = FakeAgent.new(DETAIL)

    BaseAgent.stub(:new, agent) { Location::Generator.new(room).realize! }

    assert_includes agent.prompts.sole, Location::Plan.for(room.reload).to_prompt
  end

  # AND EVERY OTHER ROOM'S PROMPT IS THE ONE A BASELINE WAS MEASURED ON. The
  # block is empty for anything with no plan, and empty means the blank line
  # that was already there -- character for character, which is what
  # `Eval::Realization::Version`'s prompt digest is comparing between runs.
  test "an ordinary room's prompt is not changed by the geometry block at all" do
    location = stub_location(name: "The Drowned Ledger")
    agent = FakeAgent.new(DETAIL, EXITS)

    realize(location, agent)

    assert_not_includes agent.prompts.first, "## Where This Room Is"
    assert_includes agent.prompts.first, "teaser: #{location.teaser}\n\n## Instructions"
  end

  # A ROOM IS STILL WRITTEN, FURNISHED AND PEOPLED. The only thing an interior
  # room does differently is its ways out; everything the detail call does is
  # the same call it makes for every other room in the game.
  test "a room inside a place gains its prose, its floor and its cast" do
    room, = laid_out_pair
    answer = DETAIL.merge("items" => FURNISHED["items"], "people" => [ PERSON ])
    agent = FakeAgent.new(answer)

    # PINNED, because a room of an interior carries no population word -- no
    # model ever named it as an exit -- so the engine rolls one, and this test
    # is about the call being made rather than about what the die said. See
    # `Location::Population`.
    Location::Population.stub(:count_for, 1) do
      BaseAgent.stub(:new, agent) { Location::Generator.new(room).realize! }
    end

    assert_predicate room.reload, :realized?
    assert_equal DETAIL["description"], room.description
    assert_equal DETAIL["lore"], room.lore
    assert_equal [ "floating ledger", "brass tide key" ], room.items.order(:id).pluck(:name)
    assert_equal [ "Maren Vosk" ], Character.present_in(room).pluck(:fullname)
  end

  # --- and what it is ASKED, which every other room is not ---------------------
  #
  # THE ROOM'S OWN NAME. `Location::Interior` numbered it before anybody walked
  # in and the number is provisional; this is the one call that can replace it,
  # and `Location::RoomName` is what decides whether the answer is taken.

  test "a room inside a place is asked to name itself, against the place it is in" do
    room, = laid_out_pair
    agent = FakeAgent.new(DETAIL)

    BaseAgent.stub(:new, agent) { Location::Generator.new(room).realize! }

    prompt = agent.prompts.sole
    assert_includes prompt, "NAME THIS ROOM"
    assert_includes prompt, "It is one room inside The Rusted Anchor."
    assert_includes prompt, %("the <your name> of The Rusted Anchor")
    assert_includes prompt, "never put the place's own name into it"
  end

  # AND EVERY OTHER ROOM'S PROMPT IS THE ONE A BASELINE WAS MEASURED ON. The
  # bullet is appended to the last instruction rather than standing in a block
  # of its own, so an empty one is not even a blank line -- `#geometry_facts`'
  # rule, and `Eval::Realization::Version`'s prompt digest is what it protects.
  test "an ordinary room is never asked to rename itself" do
    location = stub_location(name: "The Drowned Ledger")
    agent = FakeAgent.new(DETAIL, EXITS)

    realize(location, agent)

    assert_not_includes agent.prompts.first, "NAME THIS ROOM"
    assert_includes agent.prompts.first, "- Respect the stated length of each field\n\n## What Is Lying Here"
  end

  # A REFUSAL AFTER THE CALL IS A ROOM THAT KEPT ITS PLACEHOLDER over a
  # collision it was never shown, so the names already given out are stated
  # first -- `#items_instructions`' own argument.
  test "the rooms of the place that are already named are stated in the prompt" do
    room, sibling = laid_out_pair
    sibling.update!(name: "the counting room", description: "Ledgers.", lore: "Debts.",
                    detail_level: :realized)
    agent = FakeAgent.new(DETAIL)

    BaseAgent.stub(:new, agent) { Location::Generator.new(room).realize! }

    assert_includes agent.prompts.sole, "already named, so do not reuse one: the counting room"
  end

  # AND THE PLACEHOLDERS ARE NOT STATED. Nothing was ever going to propose one,
  # and a fourteen-room building would spend fourteen lines saying so.
  test "a building nobody has written yet states no taken room names at all" do
    room, = laid_out_pair
    agent = FakeAgent.new(DETAIL)

    BaseAgent.stub(:new, agent) { Location::Generator.new(room).realize! }

    assert_not_includes agent.prompts.sole, "already named, so do not reuse one"
  end

  test "a name the engine accepts is what the room is called afterwards" do
    room, = laid_out_pair
    agent = FakeAgent.new(DETAIL.merge("name" => "the counting room"))

    BaseAgent.stub(:new, agent) { Location::Generator.new(room).realize! }

    assert_equal "the counting room", room.reload.name
    assert_predicate room, :realized?
  end

  # THE PLACEHOLDER STAYS AND NOTHING RAISES, which is the whole of what a
  # refusal costs: the description that was paid for, the floor and the cast all
  # still arrive. `Location::RoomName` owns every ground; this asserts the
  # seam behaves on one of them.
  test "a name the engine refuses costs the room its name and nothing else" do
    room, = laid_out_pair
    placeholder = room.name
    answer = DETAIL.merge("name" => "The Rusted Anchor room 2", "items" => FURNISHED["items"])
    agent = FakeAgent.new(answer)

    BaseAgent.stub(:new, agent) { Location::Generator.new(room).realize! }

    assert_equal placeholder, room.reload.name
    assert_equal DETAIL["description"], room.description
    assert_equal [ "floating ledger", "brass tide key" ], room.items.order(:id).pluck(:name)
  end

  test "an answer with no name at all leaves the placeholder alone" do
    room, = laid_out_pair
    placeholder = room.name

    BaseAgent.stub(:new, FakeAgent.new(DETAIL)) { Location::Generator.new(room).realize! }

    assert_equal placeholder, room.reload.name
  end

  # THE ONE THAT MUST NOT FIRE. A room a neighbour named has a name a player may
  # already have typed, and `Location::RoomName.for` answers nil for it -- so a
  # `name` in the answer is ignored rather than honoured.
  test "a name in the answer never renames a room that is not inside a place" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL.merge("name" => "the counting room"), EXITS))

    assert_equal "The Drowned Ledger", location.reload.name
  end

  # PLAIN CONTAINMENT IS NOT AN INTERIOR, and this is the shape that tells the
  # two apart: a `parent` with NO box -- a district a street sits in, which
  # `WorldSeed::Loader#validate_one_parent!` allows and `WorldSeed::Exporter`
  # round-trips. Nothing laid a district out, so its children are ordinary
  # places: the exits call IS made, the outermost names ARE offered, and a name
  # that resolves to one of them IS honoured.
  #
  # AND AN INVENTED NAME IS BORN AT THE OUTERMOST LEVEL, not inside the
  # district. `.create_stub!` writes no `parent_location` and that is right
  # here: a street you can leave the district by opens onto somewhere outside
  # it, and nothing on record says a new place belongs to the district its
  # neighbour is in.
  test "a location inside a district with no box keeps its exits" do
    district = stub_location(name: "The Docks District")
    row = stub_location(name: "Warehouse Row", parent_location: district)
    custom_house = stub_location(name: "The Custom House")
    named = { "exits" => [
      { "name" => custom_house.name, "teaser" => "Ledgers behind shuttered glass.",
        "distance" => "adjacent", "travel_method" => "walking" },
      { "name" => "The Salt Store", "teaser" => "A door propped open with a crate.",
        "distance" => "adjacent", "travel_method" => "walking" }
    ] }
    agent = FakeAgent.new(DETAIL, named)

    BaseAgent.stub(:new, agent) { Location::Generator.new(row).realize! }

    assert_includes agent.prompts.last, custom_house.name
    assert_includes agent.prompts.last, district.name
    assert_includes row.reload.exits, custom_house
    assert LocationConnection.exists?(location: custom_house, connected_location: row)
    salt_store = @story.locations.find_by(name: "The Salt Store")
    assert_includes row.exits, salt_store
    assert_nil salt_store.parent_location_id
  end

  # AND `Story::Repair` GETS THE SAME ANSWER, because #write_exits! is where the
  # rule lives rather than #realize!: the way into a building is not something a
  # recovery may invent either.
  test "write_exits! writes nothing for a room inside a place" do
    place = stub_location(name: "The Rusted Anchor", width: 12, depth: 8)
    realize(place, FakeAgent.new(DETAIL, ONE_EXIT))
    room = place.reload.child_locations.order(:id).first
    edges = LocationConnection.count
    agent = FakeAgent.new(EXITS)

    BaseAgent.stub(:new, agent) { Location::Generator.new(room).write_exits! }

    assert_equal edges, LocationConnection.count
    assert_empty agent.schemas
  end

  # BOTH ENDS OF A DOOR HAVE THE BUDGET FOR IT, and the far side is a record
  # this room's own allowance says nothing about.
  test "an exit into a neighbour already at its cap is refused, and not half written" do
    location = stub_location(name: "The Drowned Ledger")
    full = stub_location(name: "The Pump Gallery")
    Location::ExitsSchema::MAX_EXITS.times { |n| already_reaching(full, "Filled Way #{n}") }
    named_full = { "exits" => [ EXITS["exits"].first ] }

    realize(location, FakeAgent.new(DETAIL, named_full))

    assert_empty location.reload.exits
    assert_equal Location::ExitsSchema::MAX_EXITS, full.reload.exits.count
  end

  # A LAYOUT THAT RAISES LEAVES A RETRYABLE STUB. The flip to `realized` is the
  # "generate once per place" guarantee, so a place realized on the far side of
  # a failed layout would carry a footprint and no inside for ever.
  test "a place whose layout fails is left a stub the next entry retries" do
    place = stub_location(name: "The Rusted Anchor", width: 12, depth: 8)
    exploding = ->(*) { raise ActiveRecord::RecordInvalid, Location.new }

    Location::Interior.stub(:lay_out!, exploding) do
      assert_raises(ActiveRecord::RecordInvalid) { realize(place, FakeAgent.new(DETAIL, ONE_EXIT)) }
    end

    assert_predicate place.reload, :stub?
    assert_nil place.description
    assert_empty place.child_locations

    realize(place, FakeAgent.new(DETAIL, ONE_EXIT))

    assert_predicate place.reload, :realized?
    assert_predicate place.child_locations.count, :positive?
  end

  # A ROOM IS BORN ONE WAY. `Location::Interior` creates its rooms through this
  # class method, so an interior's rooms get the danger roll a stub named by a
  # neighbour gets.
  test "a stub created through the class method is a stub with a rolled danger" do
    room = Location::Generator.create_stub!(@story, name: "The Back Room", teaser: "A door that should be locked.")

    assert_predicate room, :stub?
    assert_equal "The Back Room", room.name
    assert_includes Location::Danger::ROLLED, room.danger
  end

  test "fills in a stub's description and lore" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, EXITS))

    assert_equal DETAIL["description"], location.description
    assert_equal DETAIL["lore"], location.lore
    assert location.realized?
    assert location.persisted?
  end

  test "creates a stub location for every exit" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, EXITS))

    exits = location.reload.exits
    assert_equal [ "The Pump Gallery", "Tidewater Stair" ], exits.map(&:name).sort
    assert exits.all?(&:stub?), "exits should be stubs until the player walks into them"
    assert exits.all? { |neighbour| neighbour.teaser.present? }
  end

  test "records the connection details on the exit" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, EXITS))

    connection = LocationConnection.find_by(location: location, connected_location: Location.find_by(name: "The Pump Gallery"))
    assert_equal "across the district", connection.distance
    assert_equal "swimming", connection.travel_method
  end

  # The generator never sets it; LocationConnection works it out from the
  # distance and the method, so it cannot contradict them.
  test "the travel time is derived, not taken from the model" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, EXITS))

    connection = LocationConnection.find_by(location: location, connected_location: Location.find_by(name: "The Pump Gallery"))
    assert_equal LocationConnection.humanize_minutes(
      LocationConnection.travel_minutes("across the district", "swimming")
    ), connection.time_to_travel
  end

  # Both rows are written from one answer. They used to carry the same prose,
  # so "climb down the drainpipe to the lane below" was stored as the way up
  # as well. The enum values are direction-neutral, so identical is correct.
  test "the way back records the same distance and method, and is valid" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, EXITS))
    neighbour = Location.find_by(name: "The Pump Gallery")

    out = LocationConnection.find_by(location: location, connected_location: neighbour)
    back = LocationConnection.find_by(location: neighbour, connected_location: location)

    assert back.valid?
    assert_equal out.distance, back.distance
    assert_equal out.travel_method, back.travel_method
    assert_equal out.time_to_travel, back.time_to_travel
  end

  test "connects the exit back the way the player came" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, EXITS))

    neighbour = Location.find_by(name: "The Pump Gallery")
    assert_includes neighbour.exits, location
  end

  # The whole design: generation happens once per place, never twice.
  test "does not regenerate an already realized location" do
    location = create(:location, story: @story, name: "The Drowned Ledger")
    original = location.description

    agent = FakeAgent.new(DETAIL, EXITS)
    realize(location, agent)

    assert_empty agent.prompts
    assert_equal original, location.reload.description
    assert_empty location.exits
  end

  test "realizing a neighbour does not duplicate the location it came from" do
    location = stub_location(name: "The Drowned Ledger")
    realize(location, FakeAgent.new(DETAIL, EXITS))

    neighbour = Location.find_by(name: "The Pump Gallery")
    back_the_way_we_came = {
      "exits" => [ EXITS["exits"].first.merge("name" => "the drowned ledger") ]
    }
    realize(neighbour, FakeAgent.new(DETAIL, back_the_way_we_came))

    assert_equal 1, @story.locations.where("LOWER(name) = ?", "the drowned ledger").count
    assert_equal 1, LocationConnection.where(location: neighbour, connected_location: location).count
    assert_equal 1, LocationConnection.where(location: location, connected_location: neighbour).count
  end

  test "ignores an exit that names the location itself" do
    location = stub_location(name: "The Drowned Ledger")
    itself = { "exits" => [ EXITS["exits"].first.merge("name" => "The Drowned Ledger") ] }

    realize(location, FakeAgent.new(DETAIL, itself))

    assert_empty location.reload.exits
    assert_equal 1, @story.locations.count
  end

  test "asks for the detail schema then the exits schema" do
    agent = FakeAgent.new(DETAIL, EXITS)
    realize(stub_location, agent)

    assert_equal [ "Location::DetailSchema", "Location::ExitsSchema" ], agent.schemas.map(&:name)
  end

  # A room gets the place-shaped half of the universe -- what the world is made
  # of and who lives in it -- not how it is governed or what it believes.
  test "includes the universe and the story in the prompt" do
    agent = FakeAgent.new(DETAIL, EXITS)
    realize(stub_location(name: "The Drowned Ledger"), agent)

    assert_includes agent.prompts.first, @story.universe.geographies
    assert_includes agent.prompts.first, @story.universe.technology
    assert_includes agent.prompts.first, @story.preface
    assert_includes agent.prompts.first, "The Drowned Ledger"
  end

  test "does not spend the room prompt on how the world is governed" do
    agent = FakeAgent.new(DETAIL, EXITS)
    realize(stub_location(name: "The Drowned Ledger"), agent)

    assert_not_includes agent.prompts.first, @story.universe.politics
    assert_not_includes agent.prompts.first, @story.universe.economics
  end

  test "names the locations that already exist so exits reuse them" do
    existing = create(:location, story: @story, name: "The Pump Gallery")
    agent = FakeAgent.new(DETAIL, EXITS)
    realize(stub_location(name: "The Drowned Ledger"), agent)

    assert_includes agent.prompts.last, existing.name
  end

  test "reuses an existing location rather than inventing a second one" do
    existing = stub_location(name: "The Pump Gallery")
    location = stub_location(name: "The Drowned Ledger")

    assert_difference "Location.count", 1, "only the genuinely new exit is a new record" do
      realize(location, FakeAgent.new(DETAIL, EXITS))
    end

    assert_includes location.reload.exits, existing
  end

  # THE DEFECT THIS PINS. Realizing the hallway next to a written supply closet
  # reused the closet's name as a way out, and the edge went in both directions
  # -- so a room whose own description says "there is no other door" grew a
  # second one after the player had already read that description.
  test "does not open a new way into a room that has already been written" do
    written = create(:location, story: @story, name: "The Pump Gallery")
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, EXITS))

    assert_not_includes location.reload.exits, written
    assert_empty written.reload.exits, "the written room keeps the ways out it was written with"
    assert_equal [ "Tidewater Stair" ], location.exits.map(&:name)
  end

  # The two cases reuse has to stay legal for: the way back, and a written
  # place the player can already reach. It is the connection that decides, not
  # the detail level.
  test "a written room the player can already reach stays an exit" do
    written = create(:location, story: @story, name: "The Pump Gallery")
    location = stub_location(name: "The Drowned Ledger")
    create(:location_connection, location: written, connected_location: location)
    create(:location_connection, location: location, connected_location: written)

    realize(location, FakeAgent.new(DETAIL, EXITS))

    assert_includes location.reload.exits, written
    assert written.reload.realized?, "reusing a location must not downgrade it to a stub"
  end

  # THE FLOOR. Refusing every way out would seal the player in, which is worse
  # than a way out that should not be there, so the refusal is lifted rather
  # than a room realized with nothing leading anywhere.
  test "takes a written room as an exit rather than realize a room with no way out" do
    written = create(:location, story: @story, name: "Tidewater Stair")
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, ONE_EXIT))

    assert_equal [ written ], location.reload.exits.to_a
  end

  test "marks the places already written so the model does not spend an exit on one" do
    create(:location, story: @story, name: "The Pump Gallery")
    agent = FakeAgent.new(DETAIL, EXITS)
    realize(stub_location(name: "The Drowned Ledger"), agent)

    assert_includes agent.prompts.last, "The Pump Gallery (already written -- do not open a new way into it)"
    assert_includes agent.prompts.last, "do not open a new way into it"
  end

  test "strips emoji from generated text" do
    location = stub_location
    realize(location, FakeAgent.new(DETAIL.merge("lore" => "Two hundred years 🌊"), EXITS))

    assert_equal "Two hundred years", location.lore
  end

  test "raises when the model call fails" do
    failing = Object.new
    def failing.with_instructions(_) = self
    def failing.with_schema(_) = self
    def failing.ask(_) = raise(RubyLLM::Error.new(nil, "boom"))

    assert_raises(RubyLLM::Error) { realize(stub_location, failing) }
  end

  # The description is the expensive call of the two. It used to be held
  # unsaved until the exits came back, so an exits failure threw it away.
  test "keeps the description it already paid for when exits fail" do
    location = stub_location(name: "The Drowned Ledger")
    broken = { "exits" => [ EXITS["exits"].first.merge("distance" => "80 meters") ] }

    assert_raises(ActiveRecord::RecordInvalid) do
      realize(location, FakeAgent.new(DETAIL, broken))
    end

    assert location.reload.realized?
    assert_equal DETAIL["description"], location.description
  end

  test "writes no partial exits when one of them fails" do
    location = stub_location(name: "The Drowned Ledger")
    broken = { "exits" => [ EXITS["exits"].first, EXITS["exits"].last.merge("travel_method" => "wading") ] }

    assert_raises(ActiveRecord::RecordInvalid) do
      realize(location, FakeAgent.new(DETAIL, broken))
    end

    assert_empty location.reload.exits
    assert_equal 1, @story.locations.count
  end

  # Recovering from that failure means finishing the exits, not realizing the
  # room again -- realize! returns an already-realized location untouched.
  test "write_exits! finishes a room whose exits call failed" do
    location = stub_location(name: "The Drowned Ledger")
    broken = { "exits" => [ EXITS["exits"].first.merge("distance" => "80 meters") ] }

    assert_raises(ActiveRecord::RecordInvalid) { realize(location, FakeAgent.new(DETAIL, broken)) }

    BaseAgent.stub(:new, FakeAgent.new(EXITS)) do
      Location::Generator.new(location.reload).write_exits!
    end

    assert_equal 2, location.reload.exits.count
    assert_equal DETAIL["description"], location.description
  end

  # Story::Generator already named the opening room from the same call that
  # wrote the preface, so `.opening` only writes it out -- two calls, not three.
  test "opening realizes the stub the story generator already created" do
    opening = stub_location(name: "The Drowned Ledger", teaser: OPENING["teaser"])
    agent = FakeAgent.new(DETAIL, EXITS)

    location = BaseAgent.stub(:new, agent) { Location::Generator.opening(@story) }

    assert_equal opening, location
    assert_equal "The Drowned Ledger", location.name
    assert_equal OPENING["teaser"], location.teaser
    assert location.realized?
    assert_equal [ "Location::DetailSchema", "Location::ExitsSchema" ], agent.schemas.map(&:name)
    assert_equal 2, location.exits.count
  end

  test "opening realizes the story's oldest location, not a later stub" do
    opening = stub_location(name: "The Drowned Ledger")
    stub_location(name: "Somewhere Else")

    location = BaseAgent.stub(:new, FakeAgent.new(DETAIL, EXITS)) do
      Location::Generator.opening(@story)
    end

    assert_equal opening, location
  end

  test "opening raises rather than inventing a room the story does not have" do
    assert_raises(ArgumentError) { Location::Generator.opening(@story) }
  end
  test "realizes a room with a single way out" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, ONE_EXIT))

    exits = location.reload.exits
    assert_equal [ "Tidewater Stair" ], exits.map(&:name)
    assert location.realized?

    neighbour = exits.first
    assert_includes neighbour.exits, location, "the one way out still goes both ways"
  end

  # The dead end: the only exit is back the way the player came, and that
  # connection was written when this room was still a stub. Naming it is honest
  # and costs nothing -- no second room, no duplicated edge.
  test "a dead end whose only exit is the way back adds nothing new" do
    location = stub_location(name: "The Drowned Ledger")
    realize(location, FakeAgent.new(DETAIL, ONE_EXIT))

    dead_end = Location.find_by(name: "Tidewater Stair")
    the_way_back = { "exits" => [ EXITS["exits"].last.merge("name" => "The Drowned Ledger") ] }

    assert_no_difference [ "Location.count", "LocationConnection.count" ] do
      realize(dead_end, FakeAgent.new(DETAIL, the_way_back))
    end

    assert dead_end.reload.realized?
    assert_equal [ location ], dead_end.exits.to_a
  end

  # --- the cap is on the room, not on the answer -----------------------------

  # THE ROOFTOP. Larkspur Quarter rooftops was seeded with two edges, was
  # walked into, and came back with FIVE: `max_items: 4` bounds one answer, and
  # a room's edges also arrive from a world file and from every neighbour that
  # named it on the way to being realized. It ended up the most connected room
  # in the database, and its own description named none of them.
  test "a seeded stub with two edges does not come back with five" do
    location = stub_location(name: "Larkspur Quarter rooftops")
    2.times { |n| already_reaching(location, "Seeded Neighbour #{n}") }

    realize(location, FakeAgent.new(DETAIL, FOUR_EXITS))

    assert_equal Location::ExitsSchema::MAX_EXITS, location.reload.exits.count
    assert_equal 2, location.exits.count { |exit| exit.name.start_with?("Seeded") },
                 "the edges it arrived with are still there"
  end

  test "a room already at the cap is not asked for exits at all" do
    location = stub_location(name: "The Drowned Ledger")
    Location::ExitsSchema::MAX_EXITS.times { |n| already_reaching(location, "Neighbour #{n}") }

    agent = FakeAgent.new(DETAIL)
    assert_no_difference [ "Location.count", "LocationConnection.count" ] do
      realize(location, agent)
    end

    assert location.reload.realized?, "it is still written out in full"
    assert_equal 1, agent.prompts.count, "the detail call, and no exits call"
  end

  # --- how populated the place that way is ------------------------------------
  #
  # The captain's ruling of 2026-09-07: the narrator picks how populated a place
  # is, from a closed list, and the engine rolls the count inside that word's
  # band. The pick rides on THIS call because the count has to be known before
  # that room's own detail prompt is built -- see `Location::Population`.

  test "the word the answer picked for a place is written on the stub" do
    location = stub_location(name: "The Drowned Ledger")
    agent = FakeAgent.new(DETAIL, EXITS)

    realize(location, agent)

    assert_equal "a crowd", @story.locations.find_by(name: "The Pump Gallery").population
  end

  # A MODEL THAT LEAVES IT OUT COSTS THE ROOM ITS PICK AND NOTHING ELSE: the
  # stub is written with no word, and the engine rolls one when somebody walks
  # in. Nothing depends on the answer arriving, which is the standing constraint.
  test "an exit with no word is a stub the engine will decide for" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, EXITS))

    assert_nil @story.locations.find_by(name: "Tidewater Stair").population
  end

  test "a word the table has no band for is not written" do
    location = stub_location(name: "The Drowned Ledger")
    answer = { "exits" => [ EXITS["exits"].first.merge("population" => "heaving") ] }

    realize(location, FakeAgent.new(DETAIL, answer))

    assert_nil @story.locations.find_by(name: "The Pump Gallery").population
  end

  # AND A PLACE THAT ALREADY EXISTS KEEPS ITS OWN WORD. A neighbour's guess must
  # not overwrite what a seed file wrote or what the room the player has already
  # walked into was born with.
  test "naming a place that already exists does not repaint its population" do
    location = stub_location(name: "The Drowned Ledger")
    known = create(:location, :stub, story: @story, name: "The Pump Gallery", population: "nobody")

    realize(location, FakeAgent.new(DETAIL, EXITS))

    assert_equal "nobody", known.reload.population
  end

  # AND THE MODEL IS TOLD WHAT MAKES A PLACE BUSY, which is the inform half. It
  # is a prompt sentence and nothing rests on it: the engine takes a word it
  # recognises and rolls its own for anything else.
  test "the exits prompt says what peoples a place and what empties one" do
    location = stub_location(name: "The Drowned Ledger")
    agent = FakeAgent.new(DETAIL, EXITS)

    realize(location, agent)

    assert_match(/Say how populated each place is, in one of the words offered/, agent.prompts.last)
    assert_match(/Neither answer is the\n?\s*safe one/, agent.prompts.last)
  end

  test "the room's remaining allowance is what the model is asked for" do
    location = stub_location(name: "The Drowned Ledger")
    already_reaching(location, "Tidewater Stair")

    agent = FakeAgent.new(DETAIL, EXITS)
    realize(location, agent)

    assert_includes agent.prompts.last, "Name AT MOST 3 ways out"
    assert_includes agent.prompts.last, "Where This Room Already Leads"
    assert_includes agent.prompts.last, "Tidewater Stair"
  end

  test "a room with no edges yet is told so and gets the whole allowance" do
    agent = FakeAgent.new(DETAIL, EXITS)
    realize(stub_location(name: "The Drowned Ledger"), agent)

    assert_includes agent.prompts.last, "no ways out yet"
    assert_includes agent.prompts.last, "Name AT MOST 4 ways out"
  end

  # Naming a neighbour the room already reaches is a no-op, so it must not
  # spend the allowance -- otherwise the way back would cost a real exit.
  test "naming the way back does not use up the allowance" do
    location = stub_location(name: "The Drowned Ledger")
    back = already_reaching(location, "Tidewater Stair")

    the_way_back_and_more = { "exits" => [
      EXITS["exits"].last.merge("name" => back.name),
      *FOUR_EXITS["exits"].first(3)
    ] }

    realize(location, FakeAgent.new(DETAIL, the_way_back_and_more))

    assert_equal Location::ExitsSchema::MAX_EXITS, location.reload.exits.count
    assert_includes location.exits, back
  end

  test "tells the model that one way out is a complete answer" do
    agent = FakeAgent.new(DETAIL, EXITS)
    realize(stub_location(name: "The Drowned Ledger"), agent)

    assert_includes agent.prompts.last, "One way out is a complete answer"
    assert_includes agent.prompts.last, "Never invent a passage"
  end
  # WHAT IS LYING IN THE ROOM, written out of the same answer that described
  # it. This is the whole of `ta-item-registry`: before it, `Item` rows existed
  # only where a person had hand-written one into a seed file, so a generated
  # room was always empty and `take` could not be exercised anywhere the world
  # wrote itself.
  test "writes the things lying in the room out of the same call" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(FURNISHED, EXITS))

    assert_equal [ "floating ledger", "brass tide key" ], Item.lying_in(location).order(:id).map(&:name)
    assert_equal "A ledger swollen with water, still legible.", Item.lying_in(location).order(:id).first.description
  end

  # The closed set `Playthrough::Classifier` resolves a `take` against picks
  # generated items up with no further change, which is the point of writing
  # them as records rather than as prose.
  test "what it writes is on the floor, which is the set take reads" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(FURNISHED, EXITS))

    assert Item.lying_in(location).all?(&:lying?)
    assert_empty Item.lying_in(location).select(&:held?)
  end

  # Two calls, not three. The items are a field on the detail answer.
  test "furnishing the room costs no extra model call" do
    location = stub_location(name: "The Drowned Ledger")
    agent = FakeAgent.new(FURNISHED, EXITS)

    realize(location, agent)

    assert_equal 2, agent.prompts.size
    assert_equal [ "Location::DetailSchema", "Location::ExitsSchema" ], agent.schemas.map(&:name)
  end

  test "a room the model furnished with nothing is furnished with nothing" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL.merge("items" => []), EXITS))

    assert_equal 0, Item.lying_in(location).count
  end

  # An omitted `items` and an empty one mean the same thing. The field is
  # optional precisely so a model may leave it out.
  test "a model that omits the field leaves the room empty rather than failing" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, EXITS))

    assert location.reload.realized?
    assert_equal 0, Item.lying_in(location).count
  end

  # The registry decides, not the model. A name it refuses costs the room its
  # furniture and never its description -- the expensive half of the call is
  # already saved by then.
  test "a refused item name does not cost the room its description" do
    create(:character, story: @story, fullname: "floating ledger")
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(FURNISHED, EXITS))

    assert_equal DETAIL["description"], location.reload.description
    assert_equal [ "brass tide key" ], Item.lying_in(location).map(&:name)
  end

  test "stops at what the room may hold however many the model named" do
    location = stub_location(name: "The Drowned Ledger")
    create(:item, :lying, location: location, name: "seeded oar")
    create(:item, :lying, location: location, name: "seeded bell")

    realize(location, FakeAgent.new(FURNISHED, EXITS))

    assert_equal Item::Registry::MAX_PER_ROOM, Item.lying_in(location).count
  end

  # ASKED FOR AT MOST WHAT IS LEFT, the way the exits prompt is. A refusal
  # after the call is a room with less in it than the model thought it had
  # furnished, so the allowance is said before the call rather than only
  # enforced after it.
  test "tells the model how much room is left on the floor" do
    location = stub_location(name: "The Drowned Ledger")
    create(:item, :lying, location: location, name: "seeded oar")
    agent = FakeAgent.new(FURNISHED, EXITS)

    realize(location, agent)

    assert_match(/AT MOST 2 portable things/, agent.prompts.first)
  end

  test "asks a full room for nothing at all" do
    location = stub_location(name: "The Drowned Ledger")
    Item::Registry::MAX_PER_ROOM.times { |n| create(:item, :lying, location: location, name: "seeded #{n}") }
    agent = FakeAgent.new(DETAIL, EXITS)

    realize(location, agent)

    assert_match(/Do not list any items/, agent.prompts.first)
  end

  # The names already spoken for, said up front so an item is not spent on one.
  # Both collisions the registry refuses afterwards anyway.
  test "names what is already spoken for in this story" do
    create(:character, story: @story, fullname: "Maren Vosk")
    create(:item, :lying, location: create(:location, story: @story, name: "Elsewhere"), name: "tide key")
    location = stub_location(name: "The Drowned Ledger")
    agent = FakeAgent.new(FURNISHED, EXITS)

    realize(location, agent)

    assert_match(/do not reuse:.*Maren Vosk/, agent.prompts.first)
    assert_match(/do not reuse:.*tide key/, agent.prompts.first)
  end

  test "does not furnish a room it declined to realize" do
    location = create(:location, story: @story, name: "The Drowned Ledger")

    realize(location, FakeAgent.new(FURNISHED, EXITS))

    assert_equal 0, Item.lying_in(location).count
  end
  # --- who the room is born with --------------------------------------------
  #
  # The captain's ruling: *"rooms should be born with people in them
  # sometimes."* The same shape as the furniture above it -- structured records
  # out of the call that describes the room, never a narrator tool and never a
  # scan of prose.

  test "a person the model named is created and placed in the realized room" do
    location = stub_location(name: "The Drowned Ledger")

    assert_difference -> { Character.count }, 1 do
      realize(location, FakeAgent.new(PEOPLED, EXITS))
    end

    maren = Character.present_in(location).sole
    assert_equal "Maren Vosk", maren.fullname
    assert_equal "Maren", maren.nickname
    assert_equal PERSON["appearance"], maren.appearance
    assert_includes @story.universe.races, maren.race
  end

  # Two calls, not three: the cast is a field on the detail answer, the same way
  # the furniture is.
  test "peopling the room costs no extra model call" do
    location = stub_location(name: "The Drowned Ledger")
    agent = FakeAgent.new(PEOPLED, EXITS)

    realize(location, agent)

    assert_equal 2, agent.prompts.size
    assert_equal [ "Location::DetailSchema", "Location::ExitsSchema" ], agent.schemas.map(&:name)
  end

  # NOBODY IS THE ORDINARY ANSWER, and an omitted `people` and an empty one mean
  # the same thing -- the field is optional precisely so a model may leave it
  # out rather than fail its own realization.
  test "a room the model peopled with nobody is peopled with nobody" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL.merge("people" => []), EXITS))

    assert location.reload.realized?
    assert_equal [], Character.present_in(location).to_a
  end

  test "a model that omits the field leaves the room empty of people rather than failing" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, EXITS))

    assert location.reload.realized?
    assert_equal [], Character.present_in(location).to_a
  end

  # The registry decides, not the model, and a refusal costs the room a person
  # and never its description.
  test "a refused person name does not cost the room its description" do
    create(:character, story: @story, fullname: "Maren Vosk")
    location = stub_location(name: "The Drowned Ledger")

    assert_no_difference -> { Character.count } do
      realize(location, FakeAgent.new(PEOPLED, EXITS))
    end

    assert_equal DETAIL["description"], location.reload.description
  end

  # THE ROOM IS TOLD WHO IT MAY NAME AND WHO THEY ARE, before the model answers.
  # Race, age and sex are the engine's rolls, stated per slot on
  # `Character::Generator`'s rule -- so what comes back has to be a person the
  # prompt already described.
  test "the prompt states the people the engine has already decided on" do
    location = stub_location(name: "The Drowned Ledger")
    agent = FakeAgent.new(PEOPLED, EXITS)

    Location::Population.stub(:count_for, Location::Population::MOST) { realize(location, agent) }
    prompt = agent.prompts.first

    assert_match(/Write EXACTLY #{Location::Population::MOST} people/, prompt)
    assert_no_match(/NOBODY is the right answer/, prompt,
                    "the ceiling's nudge to leave the room empty is the sentence the 2026-09-07 ruling deleted")
    assert_match(/the 1st is .+, about \d+, /, prompt)
    assert_match(/the 2nd is .+, about \d+, /, prompt)
  end

  # THE SENTENCE AND THE SCHEMA ARE ONE STATEMENT. The prompt asks for exactly n
  # people and the schema handed to the same call requires exactly n, so a model
  # that answered with a different number fails the call rather than leaving a
  # room quietly written empty -- which is what the ceiling used to allow.
  test "the schema handed to the call requires exactly the people the prompt asks for" do
    location = stub_location(name: "The Drowned Ledger")
    agent = FakeAgent.new(PEOPLED, EXITS)

    Location::Population.stub(:count_for, 1) { realize(location, agent) }
    people = agent.schemas.first.new.to_json_schema[:schema][:properties][:people]

    assert_match(/Write EXACTLY 1 person/, agent.prompts.first)
    assert_equal 1, people[:minItems]
    assert_equal 1, people[:maxItems]
    assert_includes agent.schemas.first.new.to_json_schema[:schema][:required], :people
  end

  # AND AT NOUGHT IT IS THE FIELD IT ALWAYS WAS, which is the guard the design
  # rests on: an empty required array reads as an OMITTED field to
  # `BaseAgent#missing_schema_keys`, so a room the pick called empty would fail
  # its own realization and rotate looking for a model that would invent
  # somebody.
  test "a room with nobody in it is asked for nobody and required to answer nothing" do
    location = stub_location(name: "The Drowned Ledger", population: "nobody")
    agent = FakeAgent.new(DETAIL, EXITS)

    realize(location, agent)
    schema = agent.schemas.first.new.to_json_schema[:schema]

    assert_match(/Write NOBODY into this place/, agent.prompts.first)
    assert_not_includes schema[:required], :people
    assert_nil schema[:properties][:people][:minItems]
  end

  # The room the prompt described and the row that came out have to be the same
  # person: one registry, one set of rolls.
  test "the person written is the person the prompt described" do
    location = stub_location(name: "The Drowned Ledger")
    agent = FakeAgent.new(PEOPLED, EXITS)

    realize(location, agent)

    maren = Character.present_in(location).sole
    assert_match(/the 1st is #{Regexp.escape(maren.race.name)}, about #{maren.age}, #{maren.sex_label}/,
                 agent.prompts.first)
  end

  # ASKED FOR AT MOST WHAT IS LEFT, the way the exits and the items prompts are.
  test "a room already at its cast cap is asked for nobody" do
    location = stub_location(name: "The Drowned Ledger")
    Character::Registry::MAX_PER_ROOM.times { create(:character, story: @story, location: location) }
    agent = FakeAgent.new(DETAIL, EXITS)

    realize(location, agent)

    assert_match(/Write NOBODY into this place/, agent.prompts.first)
  end

  test "a world already at its cast cap is asked for nobody" do
    location = stub_location(name: "The Drowned Ledger")
    Character::Registry::MAX_PER_STORY.times { create(:character, story: @story) }
    agent = FakeAgent.new(DETAIL, EXITS)

    realize(location, agent)

    assert_match(/Write NOBODY into this place/, agent.prompts.first)
  end

  test "does not people a room it declined to realize" do
    location = create(:location, story: @story, name: "The Drowned Ledger")

    assert_no_difference -> { Character.count } do
      realize(location, FakeAgent.new(PEOPLED, EXITS))
    end
  end
end
