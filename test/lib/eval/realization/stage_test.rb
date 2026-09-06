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
      assert_equal 2, standing.people_allowance, "one of the room's three places is taken"
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

  def stage(kase, &block)
    Eval::Realization::Stage.open([ kase ]) { |stages| block.call(stages.fetch(kase.id)) }
  end
end
