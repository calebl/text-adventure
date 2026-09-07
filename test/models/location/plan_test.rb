require "test_helper"

# THE FLOOR PLAN A ROOM IS DESCRIBED AGAINST, and every assertion here is the
# same one: what this class says is what the RECORDS say, said in a sentence.
#
# The rooms are built by hand rather than rolled, because the point of each
# example is a shape -- a door in a named wall, a stair between two storeys, a
# way out of the building -- and a rolled layout would give whatever it gave.
# `Location::PlanTest#the-whole-of-a-laid-out-building` is the one that stands
# on `Location::Interior`'s own output, so the two cannot drift apart.
class Location::PlanTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @place = create(:location, :stub, story: @story, name: "The Rusted Anchor", width: 12, depth: 8)
  end

  # A room of `@place`, placed. Named for what it is in the example rather than
  # numbered, so a failure reads.
  def room(name, x:, y:, z: 0, width: 6, depth: 4)
    create(:location, :stub, story: @story, name: name, parent_location: @place,
                             x: x, y: y, z: z, width: width, depth: depth)
  end

  def join!(one, other, travel_method: Location::Interior::WALKING)
    [ [ one, other ], [ other, one ] ].each do |from, to|
      LocationConnection.create!(location: from, connected_location: to,
                                 distance: "adjacent", travel_method: travel_method)
    end
  end

  def plan_for(room) = Location::Plan.for(room.reload)

  # --- who gets a plan and who does not -------------------------------------

  test "a room placed in a place has a plan" do
    assert Location::Plan.for(room("the taproom", x: 0, y: 0))
  end

  # BOTH HALVES ARE REQUIRED, which is `Location::Generator#interior_room?`'s
  # rule: a box with no parent has nothing to be measured against, and a parent
  # with no box is plain containment.
  test "a place, an unplaced room and a box with no parent have no plan" do
    assert_nil Location::Plan.for(@place), "a place is not a room"
    assert_nil Location::Plan.for(create(:location, story: @story)), "an ordinary room is nowhere"
    assert_nil Location::Plan.for(create(:location, story: @story, x: 0, y: 0, z: 0, width: 4, depth: 4)),
               "a box with no parent is three numbers with nothing to read them in"
    assert_nil Location::Plan.for(nil)
  end

  # --- what it says ---------------------------------------------------------

  test "it states the room's size in paces and in metres" do
    plan = plan_for(room("the taproom", x: 0, y: 0, width: 6, depth: 4))

    assert_includes plan.to_prompt, "This room is 6 by 4 paces -- about 9 by 6 metres."
  end

  # THE STOREY IS AN INDEX AND NOT A HEIGHT, and the frame it is read in is said
  # out loud -- see `Location::Box`.
  test "it states which storey of which place the room is on, and how big the place is" do
    plan = plan_for(room("the loft", x: 0, y: 0, z: 1))

    assert_includes plan.to_prompt,
                    "It is on storey 1 of The Rusted Anchor, which is 12 by 8 paces across; " \
                    "storey 0 is the ground floor."
  end

  # A PARENT WITH NO FOOTPRINT IS A FAULT `Story::Doctor` REPORTS
  # (`boxes_with_no_parent_footprint`), and a prompt built from a database that
  # carries one still has to read as a sentence -- so the footprint clause goes
  # rather than emitting "which is by paces across".
  test "a placed room whose place has no footprint says nothing about the place's size" do
    nowhere = create(:location, :stub, story: @story, name: "The Sunken Vestry")
    orphan = create(:location, :stub, story: @story, name: "the vestry closet", parent_location: nowhere,
                                      x: 0, y: 0, z: 0, width: 4, depth: 3)

    plan = plan_for(orphan)

    assert_includes plan.to_prompt, "It is on storey 0 of The Sunken Vestry; storey 0 is the ground floor."
    assert_not_includes plan.to_prompt, "paces across"
    assert_nil plan.to_h["place_width"]
    assert_nil plan.to_h["place_depth"]
  end

  test "a door is named for the wall of this room it stands in" do
    taproom = room("the taproom", x: 0, y: 0, width: 6, depth: 4)
    snug = room("the snug", x: 6, y: 0, width: 6, depth: 4)
    join!(taproom, snug)

    assert_includes plan_for(taproom).to_prompt, "a door in the east wall, to the snug"
    assert_includes plan_for(snug).to_prompt, "a door in the west wall, to the taproom"
  end

  test "a stair says which way it goes and what storey it reaches" do
    taproom = room("the taproom", x: 0, y: 0, z: 0, width: 6, depth: 4)
    loft = room("the loft", x: 0, y: 0, z: 1, width: 6, depth: 4)
    join!(taproom, loft, travel_method: Location::Interior::STAIRS)

    assert_includes plan_for(taproom).to_prompt, "a stair up to the loft, on storey 1"
    assert_includes plan_for(loft).to_prompt, "a stair down to the taproom, on storey 0"
  end

  # WHERE THE STAIRWELL IS, WHEN THE RECORDS PLACE IT. There is no stairwell
  # record: what there is, is the ground the two rooms share, and a bearing is
  # named only when that ground lies plainly in one end of the room.
  test "a stair in one end of a room says which end" do
    hall = room("the long hall", x: 0, y: 0, z: 0, width: 12, depth: 8)
    landing = room("the landing", x: 9, y: 6, z: 1, width: 3, depth: 2)
    join!(hall, landing, travel_method: Location::Interior::STAIRS)

    assert_includes plan_for(hall).to_prompt, "a stair up to the landing, on storey 1, in the south-east of this room"
  end

  test "a stair standing over the whole room says only that it is there" do
    hall = room("the long hall", x: 0, y: 0, z: 0, width: 6, depth: 4)
    landing = room("the landing", x: 0, y: 0, z: 1, width: 6, depth: 4)
    join!(hall, landing, travel_method: Location::Interior::STAIRS)

    assert_includes plan_for(hall).to_prompt, "a stair up to the landing, on storey 1."
    assert_nil plan_for(hall).to_h["stairs"].sole["bearing"], "nothing places the stairwell in one end"
  end

  # THE WAY IN. A place's own doorway lands on a room and the far side is
  # outside the building, where this room's plane does not reach -- so it is
  # named as a way out with no wall rather than given one.
  test "an edge to somewhere outside the place is a way out with no wall" do
    taproom = room("the taproom", x: 0, y: 0)
    street = create(:location, story: @story, name: "Mournwell Lane")
    join!(taproom, street)

    prompt = plan_for(taproom).to_prompt
    assert_includes prompt, "a way out to Mournwell Lane, which is outside The Rusted Anchor"
    assert_not_includes prompt, "wall, to Mournwell Lane"
  end

  # A FAULT IS DESCRIBED HONESTLY RATHER THAN GIVEN A WALL. Two rooms of one
  # place with a connection and no shared wall is `Story::Doctor`'s
  # `door_between_rooms_that_share_no_wall`, and a prompt built from a database
  # that carries one still has to say something true.
  test "two rooms joined across a gap are a way out with no wall" do
    taproom = room("the taproom", x: 0, y: 0, width: 4, depth: 4)
    far = room("the cellar door", x: 8, y: 0, width: 4, depth: 4)
    join!(taproom, far)

    assert_includes plan_for(taproom).to_prompt, "a way out to the cellar door"
  end

  test "a room nothing leads out of says so" do
    assert_includes plan_for(room("the strongroom", x: 0, y: 0)).to_prompt, "Nothing leads out of this room yet."
  end

  # THE CLOSED SET, STATED AS A FACT. The cheap half of the standing constraint,
  # said the way `Playthrough::Moment` says it about exits.
  test "the ways out are stated as every way out there is" do
    taproom = room("the taproom", x: 0, y: 0, width: 6, depth: 4)
    join!(taproom, room("the snug", x: 6, y: 0, width: 6, depth: 4))

    assert_includes plan_for(taproom).to_prompt,
                    "Those are every way out of this room, and no other wall of it holds a door."
  end

  # ONE ORDER, WHATEVER ORDER THE ROWS WERE WRITTEN IN, so two readings of one
  # room list its doors the same way.
  test "the doors are listed in compass order however the rows were written" do
    taproom = room("the taproom", x: 4, y: 4, width: 4, depth: 4)
    south = room("the cellar stair head", x: 4, y: 8, width: 4, depth: 4)
    north = room("the porch", x: 4, y: 0, width: 4, depth: 4)
    join!(taproom, south)
    join!(taproom, north)

    assert_equal [ "north", "east", "south", "west" ] & plan_for(taproom).to_h["doors"].map { |d| d["wall"] },
                 plan_for(taproom).to_h["doors"].map { |d| d["wall"] }
    assert_equal [ "the porch", "the cellar stair head" ], plan_for(taproom).to_h["doors"].map { |d| d["to"] }
  end

  # --- the same facts as records --------------------------------------------

  test "the records a checker reads are the ones the sentences were built from" do
    taproom = room("the taproom", x: 0, y: 0, z: 0, width: 6, depth: 4)
    snug = room("the snug", x: 6, y: 0, z: 0, width: 6, depth: 4)
    loft = room("the loft", x: 0, y: 0, z: 1, width: 6, depth: 4)
    street = create(:location, story: @story, name: "Mournwell Lane")
    join!(taproom, snug)
    join!(taproom, loft, travel_method: Location::Interior::STAIRS)
    join!(taproom, street)

    assert_equal({ "room" => "the taproom", "place" => "The Rusted Anchor", "storey" => 0,
                   "place_width" => 12, "place_depth" => 8,
                   "width" => 6, "depth" => 4,
                   "doors" => [ { "wall" => "east", "to" => "the snug" } ],
                   "stairs" => [ { "to" => "the loft", "up" => true, "storey" => 1, "bearing" => nil } ],
                   "other_ways_out" => [ "Mournwell Lane" ] },
                 plan_for(taproom).to_h)
  end

  # --- and the same thing over a building nobody drew ------------------------

  # THE ONE EXAMPLE THAT IS NOT HAND-BUILT. Every other test here places its own
  # rooms to reach a shape; this one takes `Location::Interior`'s own output and
  # asserts that every sentence about it is true of the boxes and the rows --
  # which is what stops this class and the layout generator drifting apart.
  test "every room of a laid-out building is described by its own records" do
    place = create(:location, :stub, story: @story, name: "The Custom House", width: 14, depth: 10)
    Location::Interior.lay_out!(place)

    place.child_locations.order(:id).each do |built|
      plan = Location::Plan.for(built)
      facts = plan.to_h

      assert_equal built.box.width, facts["width"]
      assert_equal built.box.z, facts["storey"]
      assert_equal built.exits.count, facts["doors"].size + facts["stairs"].size + facts["other_ways_out"].size,
                   "#{built.name}: every row is described exactly once"

      facts["doors"].each do |door|
        far = @story.locations.find_by!(name: door["to"])
        assert_equal door["wall"], built.box.wall_towards(far.box),
                     "#{built.name}: the wall is the one the two boxes share"
      end
      facts["stairs"].each do |stair|
        far = @story.locations.find_by!(name: stair["to"])
        assert built.box.shares_ground?(far.box), "#{built.name}: a stair joins rooms that stand over each other"
        assert_equal far.box.z, stair["storey"]
      end
    end
  end
end
