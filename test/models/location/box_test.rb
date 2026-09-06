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
