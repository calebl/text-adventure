require "test_helper"

# WHERE IN A ROOM A THING IS, and it costs nothing to exercise: like
# `Location::BoxTest`, none of this needs a story, a universe or a save. See
# `Location::Spot`.
class Location::SpotTest < ActiveSupport::TestCase
  def row(**overrides)
    { "x" => nil, "y" => nil }.merge(overrides.transform_keys(&:to_s))
  end

  def box(x: 0, y: 0, z: 0, width: 4, depth: 3)
    Location::Box.new(x: x, y: y, z: z, width: width, depth: depth)
  end

  # --- the two whole shapes, and the broken one -----------------------------

  test "a row with neither column is unplaced" do
    assert_equal :none, Location::Spot.shape(row)
    assert_nil Location::Spot.of(row)
    assert_not Location::Spot.partial?(row)
  end

  test "both columns is a spot" do
    assert_equal :spot, Location::Spot.shape(row(x: 3, y: 5))
    assert_equal Location::Spot.new(x: 3, y: 5), Location::Spot.of(row(x: 3, y: 5))
    assert_not Location::Spot.partial?(row(x: 3, y: 5))
  end

  # HALF A POSITION IS A DEFECT, and unlike a box there is no third whole
  # answer: nothing sits at the top of this tree with one number and no other.
  test "one column of the two is partial and is not a spot" do
    [ row(x: 3), row(y: 5) ].each do |attributes|
      assert_equal :partial, Location::Spot.shape(attributes)
      assert Location::Spot.partial?(attributes)
      assert_nil Location::Spot.of(attributes)
    end
  end

  # ZERO IS A CELL AND NOT AN ABSENCE, which is what `.present?` on an integer
  # would get wrong if these read the columns any other way.
  test "a spot at the origin is a whole spot" do
    assert_equal :spot, Location::Spot.shape(row(x: 0, y: 0))
    assert_equal Location::Spot.new(x: 0, y: 0), Location::Spot.of(row(x: 0, y: 0))
  end

  # A ROOM MAY SIT WEST OF ITS PARENT'S ORIGIN, so a cell of its floor may be a
  # negative number -- which is why neither column carries a `greater_than`.
  test "a negative spot is a whole spot" do
    assert_equal Location::Spot.new(x: -4, y: -1), Location::Spot.of(row(x: -4, y: -1))
  end

  test "a spot reads from a record as well as a hash" do
    item = build(:item, :placed, x: 6, y: 2)

    assert_equal Location::Spot.new(x: 6, y: 2), Location::Spot.of(item)
  end

  # --- inside a box ----------------------------------------------------------

  # HALF-OPEN ON BOTH AXES, like every interval in this programme: the far wall
  # is not a cell of the floor. So a thing on the shared wall of two rooms is in
  # the further one and never in both.
  test "a box contains its own cells and not the walls past them" do
    room = box(x: 0, y: 0, width: 4, depth: 3)

    assert room.contains?(Location::Spot.new(x: 0, y: 0))
    assert room.contains?(Location::Spot.new(x: 3, y: 2))
    assert_not room.contains?(Location::Spot.new(x: 4, y: 0))
    assert_not room.contains?(Location::Spot.new(x: 0, y: 3))
    assert_not room.contains?(Location::Spot.new(x: -1, y: 0))
  end

  # THE FRAME IS THE PARENT'S PLANE AND NOT THE ROOM'S OWN, which is the
  # decision `Location::Spot`'s header turns on: a cell of a room that starts at
  # x = 7 is a number in the seventies of paces, not a number from zero.
  test "a room away from the origin is read in its parent's plane" do
    back = box(x: 7, y: 0, width: 5, depth: 8)

    assert back.contains?(Location::Spot.new(x: 9, y: 3))
    assert_not back.contains?(Location::Spot.new(x: 3, y: 3))
  end

  test "no box contains nowhere" do
    assert_not box.contains?(nil)
  end

  # --- the roll --------------------------------------------------------------

  # EVERY CELL AND NOTHING BUT, over enough draws to visit all of them: the
  # arithmetic is what this asserts, and `Location::PlacementTest` asserts which
  # generator it comes out of.
  test "a rolled spot is always a cell of the box it was drawn from" do
    room = box(x: 7, y: 2, width: 5, depth: 3)
    rng = Random.new(20260906)
    drawn = 200.times.map { Location::Spot.inside(room, rng: rng) }

    drawn.each { |spot| assert room.contains?(spot), "#{spot} is outside #{room}" }
    assert_equal (7...12).to_a, drawn.map(&:x).uniq.sort
    assert_equal (2...5).to_a, drawn.map(&:y).uniq.sort
  end

  # A ROOM ONE PACE ACROSS HAS ONE CELL, and the roll answers it rather than
  # dividing by anything.
  test "a one-cell box always rolls its one cell" do
    room = box(x: 4, y: 9, width: 1, depth: 1)

    assert_equal Location::Spot.new(x: 4, y: 9), Location::Spot.inside(room, rng: Random.new(1))
  end

  # ONE SEED, ONE ANSWER -- `Roll`'s whole doctrine, and the reason the two
  # draws are in a fixed order.
  test "the same generator gives the same spot" do
    room = box(x: 0, y: 0, width: 9, depth: 9)

    assert_equal Location::Spot.inside(room, rng: Random.new(77)),
                 Location::Spot.inside(room, rng: Random.new(77))
  end

  test "a spot says where it is in one phrase" do
    assert_equal "at 3,5", Location::Spot.new(x: 3, y: 5).to_s
  end
end
