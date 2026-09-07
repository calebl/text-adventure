require "test_helper"

# THE ONE PIECE OF THIS PROGRAMME THAT MUST BE EXACT, and the whole reason it is
# a value object rather than a concern: none of this needs a story, a universe
# or a save. See `Location::Box`.
class Location::BoxTest < ActiveSupport::TestCase
  def box(x: 0, y: 0, z: 0, width: 2, depth: 2)
    Location::Box.new(x: x, y: y, z: z, width: width, depth: depth)
  end

  def row(**overrides)
    { "x" => nil, "y" => nil, "z" => nil, "width" => nil, "depth" => nil }.merge(overrides.transform_keys(&:to_s))
  end

  # --- the three whole shapes, and the broken one ---------------------------

  test "a row with none of the five columns has no interior" do
    assert_equal :none, Location::Box.shape(row)
    assert_nil Location::Box.of(row)
    assert_not Location::Box.partial?(row)
  end

  # AN EXTENT WITH NO POSITION IS A WHOLE ANSWER, and it is the one that makes
  # an interior possible at all: something has to sit at the top of the
  # containment tree, and it has no frame to state a position in.
  test "an extent with no position is a footprint" do
    assert_equal :footprint, Location::Box.shape(row(width: 12, depth: 8))
    assert_not Location::Box.partial?(row(width: 12, depth: 8))
  end

  test "a footprint is not a box, because it has nowhere to be" do
    assert_nil Location::Box.of(row(width: 12, depth: 8))
  end

  test "all five columns is a box" do
    attributes = row(x: 1, y: 2, z: 0, width: 3, depth: 4)

    assert_equal :box, Location::Box.shape(attributes)
    assert_equal box(x: 1, y: 2, z: 0, width: 3, depth: 4), Location::Box.of(attributes)
  end

  # ZERO IS A COORDINATE AND NOT AN ABSENCE. `0.present?` is true in Rails and
  # this is the assertion that keeps it that way: a room at the origin of its
  # parent is the commonest room there is.
  test "a box at the origin of its parent is a whole box" do
    assert_equal :box, Location::Box.shape(row(x: 0, y: 0, z: 0, width: 1, depth: 1))
  end

  test "part of a position, or a position with no extent, is partial" do
    assert_equal :partial, Location::Box.shape(row(x: 1, y: 2))
    assert_equal :partial, Location::Box.shape(row(x: 1, y: 2, z: 0))
    assert_equal :partial, Location::Box.shape(row(width: 3))
    assert_equal :partial, Location::Box.shape(row(x: 1, y: 2, z: 0, width: 3))
    assert_nil Location::Box.of(row(x: 1, y: 2, z: 0, width: 3))
  end

  # --- overlap, which is exact -----------------------------------------------

  test "two boxes in the same place overlap" do
    assert box(x: 0, y: 0, width: 3, depth: 3).overlaps?(box(x: 1, y: 1, width: 3, depth: 3))
  end

  # HALF-OPEN INTERVALS, and this is the assertion that pins them. A room at
  # x = 0 three wide occupies 0, 1 and 2; a room at x = 3 begins where it ends.
  # If this ever fails, no door can be put on a shared wall in slice 2.
  test "two rooms sharing a wall are touching and not overlapping" do
    assert_not box(x: 0, y: 0, width: 3, depth: 8).overlaps?(box(x: 3, y: 0, width: 3, depth: 8))
    assert_not box(x: 0, y: 0, width: 8, depth: 3).overlaps?(box(x: 0, y: 3, width: 8, depth: 3))
  end

  test "a one pace gap is not an overlap" do
    assert_not box(x: 0, y: 0, width: 3, depth: 3).overlaps?(box(x: 4, y: 0, width: 3, depth: 3))
  end

  test "overlap is symmetric" do
    one = box(x: 0, y: 0, width: 5, depth: 5)
    other = box(x: 4, y: 4, width: 5, depth: 5)

    assert one.overlaps?(other)
    assert other.overlaps?(one)
  end

  # 2.5D, THE CAPTAIN'S THIRD RULING: a floor is its own plane, so a room
  # directly above another shares nothing with it. A check that said otherwise
  # would be reporting a building for having two storeys.
  test "the same rectangle on two storeys does not overlap" do
    assert_not box(z: 0, width: 5, depth: 5).overlaps?(box(z: 1, width: 5, depth: 5))
    assert_not box(z: 0, width: 5, depth: 5).overlaps?(box(z: -1, width: 5, depth: 5))
  end

  test "a box contains itself" do
    assert box.overlaps?(box)
  end

  # --- the value ------------------------------------------------------------

  test "two boxes with the same five numbers are the same box" do
    assert_equal box(x: 1, y: 2, z: 3, width: 4, depth: 5), box(x: 1, y: 2, z: 3, width: 4, depth: 5)
    assert_equal box.hash, box.hash
    assert_not_equal box(x: 1), box(x: 2)
  end

  # --- the arithmetic a stair and a door are built on ------------------------

  # THE STOREY TAKEN OUT: what "floors are kept aligned" means, and the whole of
  # what `Story::Doctor` reads to decide a staircase arrives where it set off
  # from.
  test "two rooms on different storeys can still stand over each other" do
    below = box(x: 0, y: 0, z: 0, width: 6, depth: 6)
    above = box(x: 3, y: 3, z: 1, width: 6, depth: 6)

    assert_not below.overlaps?(above)
    assert below.shares_ground?(above)
  end

  test "two rooms side by side stand over nothing of each other" do
    assert_not box(x: 0, y: 0, width: 3, depth: 3).shares_ground?(box(x: 3, y: 0, z: 1, width: 3, depth: 3))
  end

  test "two rooms that share a wall could have a door in it" do
    assert box(x: 0, y: 0, width: 4, depth: 4).shares_a_wall?(box(x: 4, y: 0, width: 4, depth: 4))
    assert box(x: 0, y: 0, width: 4, depth: 4).shares_a_wall?(box(x: 0, y: 4, width: 4, depth: 4))
  end

  # A CORNER IS NOT A WALL. Two rooms meeting corner to corner touch on both
  # axes and share a run of nothing, so a door there would be a door through a
  # corner.
  test "two rooms meeting at a corner share no wall" do
    assert_not box(x: 0, y: 0, width: 4, depth: 4).shares_a_wall?(box(x: 4, y: 4, width: 4, depth: 4))
  end

  test "two rooms on different storeys share no wall, however they are placed" do
    assert_not box(x: 0, y: 0, z: 0, width: 4, depth: 4).shares_a_wall?(box(x: 4, y: 0, z: 1, width: 4, depth: 4))
  end

  test "two rooms with a gap between them share no wall" do
    assert_not box(x: 0, y: 0, width: 4, depth: 4).shares_a_wall?(box(x: 5, y: 0, width: 4, depth: 4))
  end

  # --- which wall, and which end of the room --------------------------------
  #
  # NORTH IS UP ON THE PLAN AND `y` RISES TO THE SOUTH -- the convention at the
  # top of `Location::Box`, which is a decision and not a discovery, so it is
  # pinned here in all four directions rather than inferred from one.

  test "the wall a door stands in is named for the side of this room it is on" do
    room = box(x: 4, y: 4, width: 4, depth: 4)

    assert_equal Location::Box::EAST, room.wall_towards(box(x: 8, y: 4, width: 4, depth: 4))
    assert_equal Location::Box::WEST, room.wall_towards(box(x: 0, y: 4, width: 4, depth: 4))
    assert_equal Location::Box::SOUTH, room.wall_towards(box(x: 4, y: 8, width: 4, depth: 4))
    assert_equal Location::Box::NORTH, room.wall_towards(box(x: 4, y: 0, width: 4, depth: 4))
  end

  # ONE DOORWAY, TWO ROOMS, TWO WALLS -- which is what a person walking through
  # it experiences: the east wall of the room they leave is the west wall of the
  # room they arrive in.
  test "one doorway is a different wall of each room" do
    here = box(x: 0, y: 0, width: 4, depth: 4)
    there = box(x: 4, y: 0, width: 4, depth: 4)

    assert_equal Location::Box::EAST, here.wall_towards(there)
    assert_equal Location::Box::WEST, there.wall_towards(here)
  end

  test "there is no wall towards a room that shares none" do
    room = box(x: 0, y: 0, width: 4, depth: 4)

    assert_nil room.wall_towards(box(x: 4, y: 4, width: 4, depth: 4)), "a corner is not a wall"
    assert_nil room.wall_towards(box(x: 5, y: 0, width: 4, depth: 4)), "a gap is not a wall"
    assert_nil room.wall_towards(box(x: 4, y: 0, z: 1, width: 4, depth: 4)), "another storey is another plane"
  end

  # THE WALL ITSELF, which is what `Story::Map` draws a doorway on: the axis it
  # stands on, where it stands, and the stretch the two rooms really share.
  test "a shared wall says where it stands and how much of it the two rooms have" do
    assert_equal [ :x, 4, 2, 6 ],
                 box(x: 0, y: 0, width: 4, depth: 8).shared_wall(box(x: 4, y: 2, width: 4, depth: 4))
    assert_equal [ :y, 4, 0, 4 ],
                 box(x: 0, y: 0, width: 4, depth: 4).shared_wall(box(x: 0, y: 4, width: 8, depth: 4))
  end

  # A ONE-PACE RUN IS A DOORWAY AND A ZERO-PACE RUN IS A CORNER --
  # `MINIMUM_DOORWAY`, and the boundary is where the two answers change.
  test "a wall shared for one pace can hold a door" do
    room = box(x: 0, y: 0, width: 4, depth: 4)

    assert_equal Location::Box::EAST, room.wall_towards(box(x: 4, y: 3, width: 4, depth: 4))
    assert_nil room.wall_towards(box(x: 4, y: 4, width: 4, depth: 4))
  end

  # WHERE A STAIRWELL CAN BE, and it is the only thing the records say about
  # one: a stair joins two rooms only where they stand over each other.
  test "the ground two rooms share is the region one stands over the other in" do
    below = box(x: 0, y: 0, width: 8, depth: 8)
    above = box(x: 6, y: 6, z: 1, width: 8, depth: 8)

    assert_equal box(x: 6, y: 6, z: 0, width: 2, depth: 2), below.shared_ground(above)
    assert_nil below.shared_ground(box(x: 8, y: 0, z: 1, width: 4, depth: 4)), "side by side and over nothing"
  end

  test "the shared ground is read on the storey it is asked of" do
    below = box(x: 0, y: 0, z: 0, width: 4, depth: 4)
    above = box(x: 0, y: 0, z: 3, width: 4, depth: 4)

    assert_equal 0, below.shared_ground(above).z
    assert_equal 3, above.shared_ground(below).z
  end

  # A BEARING IS A QUARTER OF THE ROOM OFF CENTRE OR IT IS NOTHING --
  # `BEARING_SHARE`, and the silence is the point: a stairwell half a pace off
  # centre named as "in the west of the room" would be a precision the records
  # do not have.
  test "a part of a room lying plainly in one end is named for that end" do
    room = box(x: 0, y: 0, width: 8, depth: 8)

    assert_equal "north-west", room.bearing_of(box(x: 0, y: 0, width: 2, depth: 2))
    assert_equal "south-east", room.bearing_of(box(x: 6, y: 6, width: 2, depth: 2))
    assert_equal "north", room.bearing_of(box(x: 3, y: 0, width: 2, depth: 2))
    assert_equal "east", room.bearing_of(box(x: 6, y: 3, width: 2, depth: 2))
  end

  test "a part in the middle of a room, or filling it, has no bearing" do
    room = box(x: 0, y: 0, width: 8, depth: 8)

    assert_nil room.bearing_of(box(x: 3, y: 3, width: 2, depth: 2))
    assert_nil room.bearing_of(room)
  end

  # THE ONE PLACE THE PACE BECOMES A LENGTH ANYBODY OUTSIDE THIS FILE SPEAKS,
  # and it is rounded because a pace is already an approximation of a stride.
  test "a room in metres is its paces at the one conversion the engine owns" do
    assert_equal [ 9, 6 ], box(width: 6, depth: 4).metres
    assert_equal [ 11, 5 ], box(width: 7, depth: 3).metres
  end

  # HALF-OPEN AGAIN: a room ending exactly on the far wall is inside the
  # building, and one pace further out is not.
  test "a room fits inside the footprint it is read in, up to the far wall" do
    assert box(x: 0, y: 0, width: 12, depth: 8).inside_footprint?(12, 8)
    assert_not box(x: 1, y: 0, width: 12, depth: 8).inside_footprint?(12, 8)
    assert_not box(x: -1, y: 0, width: 4, depth: 4).inside_footprint?(12, 8)
    assert_not box(x: 0, y: 5, width: 4, depth: 4).inside_footprint?(12, 8)
  end

  # CENTRE TO CENTRE AND BY THE STREETS, and the halves of an odd-sided room
  # are dropped rather than carried, because the answer is read as a bucket.
  test "how far apart two rooms are is measured centre to centre" do
    assert_equal 0, box(x: 0, y: 0, width: 4, depth: 4).paces_to(box(x: 0, y: 0, width: 4, depth: 4))
    assert_equal 4, box(x: 0, y: 0, width: 4, depth: 4).paces_to(box(x: 4, y: 0, width: 4, depth: 4))
    assert_equal 8, box(x: 0, y: 0, width: 4, depth: 4).paces_to(box(x: 4, y: 4, width: 4, depth: 4))
  end

  # A STOREY INDEX IS NOT A HEIGHT, so there is no number of paces a floor is
  # worth: what going up costs is the travel method.
  test "the storey is not part of how far apart two rooms are" do
    assert_equal 0, box(x: 0, y: 0, z: 0, width: 4, depth: 4).paces_to(box(x: 0, y: 0, z: 3, width: 4, depth: 4))
  end

  # WHAT THE HEADER CLAIMS OF A VALUE OBJECT, asserted rather than assumed: a box
  # is handed around between the loader, the doctor, the exporter and the sweep
  # invariant, and none of them may be able to change one under another.
  test "a box is frozen, and asking for a different one leaves the original alone" do
    box = Location::Box.new(x: 0, y: 0, z: 0, width: 5, depth: 5)
    wider = box.with(width: 9)

    assert_predicate box, :frozen?
    assert_equal 5, box.width
    assert_equal 9, wider.width
    assert_equal [ 0, 0, 0, 5 ], [ wider.x, wider.y, wider.z, wider.depth ]
  end

  test "two boxes with the same five numbers are one key in a hash" do
    one = Location::Box.new(x: 1, y: 2, z: 0, width: 5, depth: 5)
    other = Location::Box.new(x: 1, y: 2, z: 0, width: 5, depth: 5)

    assert_equal 1, { one => "here", other => "here" }.size
    assert_equal one.hash, other.hash
  end

  test "a box describes itself in one phrase, in paces" do
    assert_equal "6x4 paces at 2,3 on storey 1", box(x: 2, y: 3, z: 1, width: 6, depth: 4).to_s
  end

  # THE UNIT, NAMED ONCE. Nothing reads it until slice 3 puts dimensions in
  # front of the narrator; this is the assertion that it is a number and not a
  # comment.
  test "a pace has a length in metres" do
    assert_equal 1.5, Location::Box::METRES_PER_PACE
  end

  test "the columns are the position and the extent, in the order a file reads them" do
    assert_equal %w[x y z width depth], Location::Box::COLUMNS
    assert_equal %w[x y z], Location::Box::POSITION
    assert_equal %w[width depth], Location::Box::EXTENT
  end
end
