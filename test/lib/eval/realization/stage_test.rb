require "test_helper"

# WINDING A ROOM BACK, AND LEAVING NOTHING BEHIND.
#
# The stage is what makes a case reproducible, and it does it by DELETING ROOMS
# -- which is only safe because everything it does happens inside a transaction
# that is rolled back, in a copy of the world loaded under a title of its own.
# Both halves of that are pinned here, because a regression in either one would
# be a bench that quietly ate a development database.
class Eval::Realization::StageTest < ActiveSupport::TestCase
  test "the room is wound back to a stub with one way out, and the world keeps its title" do
    stage(kase(room: "The Long Hallway", reached_from: "Ward Office 12")) do |standing|
      room = standing.location

      assert room.stub?
      assert_nil room.description
      assert_nil room.lore
      assert_equal [ "Ward Office 12" ], standing.reachable
      assert_equal "The Unrecorded Hour", standing.story.title,
                   "the narrator is told the title, so the staging label must not survive"
    end
  end

  # THE SURGERY, ONE KEY AT A TIME.
  test "every edge but the way in is removed when no other neighbour is declared" do
    # The closet is realized in the seed and reached from the office; wound back,
    # the office is the only place it leads.
    stage(kase(room: "Ward Office 12", reached_from: "The Supply Closet")) do |standing|
      assert_equal [ "The Supply Closet" ], standing.reachable,
                   "the hallway edge is the office's own, and a room realized by being walked into has one way out"
    end
  end

  test "`absent` destroys a room, so it is not a place that already exists and not a taken name" do
    stage(kase(room: "The Long Hallway", reached_from: "Ward Office 12", absent: [ "The Supply Closet" ])) do |standing|
      assert_not_includes standing.places.map { |place| place["name"] }, "The Supply Closet"
      assert_not_includes standing.taken_names, "Perrin's private index",
                          "a destroyed room takes what was lying in it with it"
    end
  end

  test "`unwritten` leaves a room in place and takes its description away" do
    stage(kase(room: "The Long Hallway", reached_from: "Ward Office 12", unwritten: [ "The Supply Closet" ])) do |standing|
      closet = standing.places.find { |place| place["name"] == "The Supply Closet" }

      assert_not closet["realized"], "which is what makes naming it a legal exit rather than a defect"
      assert_not closet["connected"]
    end
  end

  test "`danger` overrides the room's own, so the corpus can reach the monstrous branch" do
    stage(kase(room: "The Long Hallway", reached_from: "Ward Office 12", danger: "dangerous")) do |standing|
      assert_equal "dangerous", standing.location.danger
      assert_operator standing.location.danger_share, :>, 0
    end
  end

  # WHO IS ALREADY IN THE ROOM STAYS THERE, which is deliberate: a stub may
  # legitimately have somebody in it, and a person here takes up one of the
  # room's places and puts their name in the spoken-for list. Both are states
  # the generator really meets.
  test "a person already standing in the room is left there and costs the room a slot" do
    stage(kase(room: "The Tide Post", reached_from: "The Causeway Court", story: "The Salt Assizes")) do |standing|
      assert_includes Character.present_in(standing.location).pluck(:fullname), "Neb Halloran"
      assert_includes standing.taken_names, "Neb Halloran"
      # PINNED, because the count is a roll now (`Location::Population`) and a
      # seeded room carries no word for the engine to read: what this asserts is
      # that the occupant costs the room one of its places, not what the die
      # said.
      Location::Population.stub(:count_for, Character::Registry::MAX_PER_ROOM) do
        assert_equal Character::Registry::MAX_PER_ROOM - 1, standing.people_allowance,
                     "the occupant costs the room one of its places"
      end
    end
  end

  test "the allowances are read off the records rather than assumed" do
    stage(kase(room: "Mournwell Lane", reached_from: "Grenn's Boarding House, Room 3",
               story: "The Lunar Cartographer")) do |standing|
      assert_equal Location::ExitsSchema::MAX_EXITS - 1, standing.exit_allowance
      assert_equal Item::Registry::MAX_PER_ROOM, standing.item_allowance
      assert_equal standing.people_allowance, standing.slots.size
    end
  end

  # `also_reaches` IS WHAT MAKES A MULTI-EXIT STUB REACHABLE AT ALL. Without it
  # every case stages a room with one way out and the allowance is always the
  # cap less one, so the two checks written for a room that is already partly
  # connected would never meet one.
  test "`also_reaches` keeps a seeded edge, so the stub really stands with two ways out" do
    mournwell = kase(room: "Mournwell Lane", reached_from: "Grenn's Boarding House, Room 3",
                     story: "The Lunar Cartographer", also_reaches: [ "Sovereign's Circle" ])

    stage(mournwell) do |standing|
      assert_equal [ "Grenn's Boarding House, Room 3", "Sovereign's Circle" ], standing.reachable.sort
      assert_equal Location::ExitsSchema::MAX_EXITS - 2, standing.exit_allowance,
                   "two of the room's four are already spent, and the prompt states what is left"
      assert_includes standing.generator.exits_prompt, "AT MOST #{standing.exit_allowance}"
    end
  end

  test "an `also_reaches` the room is not joined to is refused rather than staged as one way out" do
    error = assert_raises(Eval::Realization::Stage::Unstageable) do
      stage(kase(room: "Mournwell Lane", reached_from: "Grenn's Boarding House, Room 3",
                 story: "The Lunar Cartographer", also_reaches: [ "The Celestial Spire" ])) { |_| }
    end

    assert_includes error.message, "this stub could not already reach it"
  end

  # THE ROLLED CAST IS RECORDED, NOT PINNED -- `Eval::Realization::Version`'s
  # header says why at length. What has to be true is that the slots the FACTS
  # record are the slots the PROMPT was built from, which is the one thing a
  # second registry would break.
  test "the slots the facts record are the slots the prompt states" do
    stage(kase(room: "The Long Hallway", reached_from: "Ward Office 12")) do |standing|
      prompt = standing.generator.people_instructions
      standing.slots.each do |slot|
        assert_includes prompt, "#{slot["race"]}, about #{slot["age"]}, #{slot["sex"]}"
      end
    end
  end

  test "an unstageable case says which key was wrong" do
    error = assert_raises(Eval::Realization::Stage::Unstageable) do
      stage(kase(room: "The Boiler Landing", reached_from: "Ward Office 12")) { |_| }
    end

    assert_includes error.message, "has no room called \"The Boiler Landing\" (room)"
  end

  test "a world the story opens in cannot be declared absent" do
    error = assert_raises(Eval::Realization::Stage::Unstageable) do
      stage(kase(room: "The Long Hallway", reached_from: "The Supply Closet",
                 absent: [ "Ward Office 12" ])) { |_| }
    end

    assert_includes error.message, "where the story opens"
  end

  # AN INTERIOR ROOM'S EDGES ARE NOT WOUND BACK, because they were not written
  # by realizing it: `Location::Interior` decided every door and every stair in
  # one call before the room was anything but a box. Dropping one would stage a
  # room the layout never wrote and hand `Location::Plan` a floor plan with a
  # wall missing out of it.
  test "a room inside a laid-out place keeps every door, and an ordinary room keeps only the way in" do
    interior = kase(room: "The Custom House room 1", reached_from: "The Quay", story: "The Quay House")

    stage(interior) do |standing|
      assert_equal [ "The Quay", "The Custom House room 2", "The Custom House room 5" ].sort,
                   standing.reachable.sort
      assert_equal 7, standing.plan["width"]
      assert_equal "east", standing.plan["doors"].sole["wall"]
      assert_equal [ "The Quay" ], standing.plan["other_ways_out"]
    end

    stage(kase(room: "The Long Hallway", reached_from: "Ward Office 12")) do |standing|
      assert_equal [ "Ward Office 12" ], standing.reachable
      assert_nil standing.plan
    end
  end

  # WHETHER THE PROMPT WILL ASK FOR A NAME IS ASKED THROUGH THE ENGINE'S OWN
  # GATE (`Location::RoomName.for`) and not derived from the plan being present.
  # The two agree today; a checker that assumed they always would goes quietly
  # wrong the day they stop, and this is the fact both name checks put their
  # denominator behind.
  test "a room inside a laid-out place is one the prompt will ask to name itself" do
    stage(kase(room: "The Custom House room 3", reached_from: "The Custom House room 2",
               story: "The Quay House")) do |standing|
      assert standing.name_asked?
      # The Quay House ships two rooms written and both keep their placeholders,
      # so there is nothing to state as taken.
      assert_equal [], standing.name_taken
    end

    stage(kase(room: "The Long Hallway", reached_from: "Ward Office 12")) do |standing|
      assert_not standing.name_asked?
      assert_equal [], standing.name_taken
    end
  end

  # WHERE EVERY ROOM OF A BUILDING IS, which is what makes a stored row
  # DRAWABLE (`Lab::Realization::Plan`). Read off `Location`'s own `x` and `y`
  # and never recomputed, and the doors are the ones the layout actually opened
  # -- adjacency is not a door, so a drawing derived from the boxes would show a
  # building `Location::Interior` refused to build.
  test "a laid-out place records where each of its rooms is and which of them have doors between them" do
    laid_out do |standing, place|
      rooms = standing.rooms_laid_out
      records = place.child_locations.order(:id).to_a

      assert_equal records.size, rooms.size
      assert_equal (0...records.size).to_a, rooms.map { |room| room["index"] }
      rooms.zip(records).each do |stored, record|
        assert_equal record.x, stored["x"], "#{record.name} is stored at the wrong x"
        assert_equal record.y, stored["y"], "#{record.name} is stored at the wrong y"
        assert_equal record.z, stored["storey"]
        assert_equal record.name, stored["name"]
      end
    end
  end

  # A DOOR IS TWO ROWS, SO BOTH ENDS NAME IT. A one-sided entry would draw a
  # door on one room and not on its neighbour, which is a drawing that cannot be
  # read against itself.
  test "the doors a room records are recorded from the other side too" do
    laid_out do |standing, _place|
      rooms = standing.rooms_laid_out

      rooms.each do |room|
        room["doors_to"].each do |far|
          assert_includes rooms[far]["doors_to"], room["index"],
                          "#{room["name"]} says it has a door to #{rooms[far]["name"]} and that room does not"
        end
        room["stairs_to"].each do |far|
          assert_includes rooms[far]["stairs_to"], room["index"]
        end
      end
    end
  end

  # A DOOR AND A STAIR ARE TOLD APART BY `LocationConnection#travel_method` and
  # never by the two storeys differing, which would be a second answer to what a
  # stair is. Every entry in either list is a sibling: a doorway out of the
  # building has no index here, which is what keeps `doors` the honest total.
  test "a stair is not a door, and neither list ever names a room outside the building" do
    laid_out do |standing, _place|
      rooms = standing.rooms_laid_out
      indices = rooms.map { |room| room["index"] }

      # NOT VACUOUS: the fixture really has rooms with doors between them, so a
      # regression that emptied both lists would fail here rather than pass
      # silently.
      assert_operator rooms.sum { |room| room["doors_to"].size }, :>, 0

      rooms.each do |room|
        assert_empty room["doors_to"] & room["stairs_to"]
        assert_empty (room["doors_to"] + room["stairs_to"]) - indices
        assert_operator room["doors"], :>=, room["doors_to"].size + room["stairs_to"].size
      end
    end
  end

  # ------------------------------------------------- a case that carries its own room

  # THE PROMOTION, AT THE STAGE. A kind the captain typed in the lab is in no
  # world file, so a case for it has no room to FIND -- and until this class
  # could create one, a scored kind could never be re-run against a changed
  # prompt.
  test "a case with a teaser creates the stub the world does not have, and opens the way in" do
    stage(typed(room: "The Drowned Counting House", reached_from: "Ward Office 12")) do |standing|
      room = standing.location

      assert_predicate room, :stub?
      assert_equal "The Drowned Counting House", room.name
      assert_equal "A counting house half-sunk at the river's edge.", room.teaser
      assert_nil room.description
      assert_equal [ "Ward Office 12" ], standing.reachable
      assert_equal "The Unrecorded Hour", standing.story.title
      # BOTH DIRECTIONS, because the exits prompt's dead-end sentence is about
      # the place the player came from specifically.
      assert_includes standing.story.locations.find_by(name: "Ward Office 12").exits, room
    end
  end

  test "a case with a teaser is offered as a place that already exists to the rest of the world" do
    stage(typed(room: "The Drowned Counting House", reached_from: "Ward Office 12")) do |standing|
      assert_not_includes standing.places.map { |place| place["name"] }, "The Drowned Counting House",
                          "the room being built is never one of the places the prompt offers"
      assert_includes standing.taken_names, "Perrin's private index",
                      "the world around a created stub is the world's own, read off the records"
    end
  end

  test "the declared danger and inside band reach the created stub, and a band makes it a building" do
    typed_case = typed(room: "The Drowned Counting House", reached_from: "Ward Office 12",
                       danger: "dangerous", inside: "a few rooms", population: "a person or two")

    stage(typed_case) do |standing|
      assert_equal "dangerous", standing.location.danger
      assert_equal "a person or two", standing.location.population
      assert_predicate standing, :place?, "a footprint inside a band is what makes it a building"
      assert_equal 0, standing.people_allowance, "a building is asked for nobody and for nothing"
    end
  end

  test "a case with a teaser may also reach a second neighbour, and both edges are written" do
    typed_case = typed(room: "The Drowned Counting House", reached_from: "Ward Office 12",
                       also_reaches: [ "The Supply Closet" ])

    stage(typed_case) do |standing|
      assert_equal [ "The Supply Closet", "Ward Office 12" ], standing.reachable.sort
      assert_equal Location::ExitsSchema::MAX_EXITS - 2, standing.exit_allowance
    end
  end

  # AND THE ORIGINAL SHAPE IS UNTOUCHED: a case with no teaser still finds its
  # room, and a case whose room the world lost still says which key was wrong.
  test "a case with no teaser still finds a room the world has" do
    stage(kase(room: "The Long Hallway", reached_from: "Ward Office 12")) do |standing|
      assert_equal "The Long Hallway", standing.location.name
      assert_equal "The Unrecorded Hour", standing.story.title
    end
  end

  test "a case with a teaser whose room the world already has is refused rather than written twice" do
    error = assert_raises(Eval::Realization::Stage::Unstageable) do
      stage(typed(room: "The Long Hallway", reached_from: "Ward Office 12")) { |_| }
    end

    assert_includes error.message, "would write it twice"
  end

  test "a created stub's way back has to be somewhere the world really is" do
    error = assert_raises(Eval::Realization::Stage::Unstageable) do
      stage(typed(room: "The Drowned Counting House", reached_from: "The Boiler Landing")) { |_| }
    end

    assert_includes error.message, "has no room called \"The Boiler Landing\" (reached_from)"
  end

  test "nothing survives the staging of a created stub either" do
    before = [ Story.count, Location.count, LocationConnection.count ]
    stage(typed(room: "The Drowned Counting House", reached_from: "Ward Office 12")) { |_| }

    assert_equal before, [ Story.count, Location.count, LocationConnection.count ]
  end
  test "nothing survives the staging" do
    before = [ Story.count, Location.count, Character.count, Item.count, LocationConnection.count ]
    stage(kase(room: "The Long Hallway", reached_from: "Ward Office 12", absent: [ "The Supply Closet" ])) { |_| }

    assert_equal before, [ Story.count, Location.count, Character.count, Item.count, LocationConnection.count ]
  end

  private

  def kase(room:, reached_from: nil, story: "The Unrecorded Hour", also_reaches: [], absent: [],
           unwritten: [], danger: nil)
    Eval::Realization::Corpus::Case.new(
      id: "a-case", story: story, room: room, reached_from: reached_from, also_reaches: also_reaches,
      absent: absent, unwritten: unwritten, danger: danger, expects_new_ground: true,
      shape: "corridor", why: "a test"
    )
  end

  # A PLACE WITH AN INSIDE, STOOD UP IN A ROLLED-BACK COPY OF ITS WORLD. The
  # Custom House is the one building in the checked-in worlds
  # (`db/seeds/worlds`), and the standing is built on the PLACE rather than on
  # one of its rooms because `#rooms_laid_out` is a reading of a place's
  # children.
  def laid_out
    Eval::Concurrency.rolled_back do
      story = Eval::Realization::Stage.load_world!("The Quay House", title: "The Quay House (a test)")
      place = story.locations.find_by!(name: "The Custom House")
      standing = Eval::Realization::Stage::Standing.new(
        kase: kase(room: place.name, story: "The Quay House"), story: story,
        location: place, generator: Location::Generator.new(place)
      )

      yield standing, place
    end
  end

  # A CASE THAT CARRIES ITS OWN STUB. `danger` is not optional on one -- the roll
  # a new room would get is keyed on the story's id, which a staged copy is
  # issued afresh on every load -- and `Eval::Realization::Corpus` refuses a
  # typed case without it, so the default here is a declared one.
  def typed(room:, reached_from: nil, story: "The Unrecorded Hour", also_reaches: [],
            danger: "uneasy", inside: nil, population: nil)
    Eval::Realization::Corpus::Case.new(
      id: "a-typed-case", story: story, room: room,
      teaser: "A counting house half-sunk at the river's edge.",
      reached_from: reached_from, also_reaches: also_reaches, danger: danger, inside: inside,
      population: population, expects_new_ground: true, shape: "lab-promoted", why: "a test"
    )
  end

  def stage(kase, &block)
    Eval::Realization::Stage.open([ kase ]) { |stages| block.call(stages.fetch(kase.id)) }
  end
end
