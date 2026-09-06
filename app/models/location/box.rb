# WHERE A ROOM IS AND HOW BIG IT IS, and the whole of the arithmetic that
# answers whether two of them are in the same place at once.
#
# THE FOUR RULINGS OF 2026-09-06, settled on the neohack board and the reason
# every file in this programme is shaped the way it is
# (`data/ta-neohack-scout/report.md` sections 9.2 to 9.5 in firstmate):
#
#   1  HOW AN INTERIOR IS GENERATED: the whole interior is laid out on first
#      entry, and rooms are realized lazily. The geometry is decided up front so
#      connectivity can be GUARANTEED; the prose is still written one room at a
#      time as the player walks in, so what the player experiences of discovery
#      is unchanged. Not built here -- that is slice 2.
#   2  WHAT A PLACE IS, IN THE SCHEMA: a `Location` plus `parent_location`, and
#      the party stands in a CHILD room. A parent is a container the player
#      never occupies, which is what keeps every downstream reader working
#      untouched -- `Character.present_in`, `Item.lying_in` and `Scene#location`
#      all still read a room.
#   3  HOW FLOORS WORK: 2.5D, NOT 3D. A floor is its own plane and a stair is an
#      EDGE -- a `LocationConnection` with `travel_method: "taking stairs"`,
#      which the table has carried since before any of this. So overlap and
#      connectivity stay two-dimensional problems, which are exact and testable;
#      a building is realistic because its floors are KEPT ALIGNED (a stairwell
#      at (x, y) on one storey arrives at (x, y) on the next), which costs one
#      predicate instead of a geometry engine.
#   4  THE THREE SEEDED WORLDS: left flat. Every column is nullable, nothing is
#      backfilled, and interiors are opt-in per file and per generated world.
#
# COORDINATES ARE LOCAL TO A PARENT, NEVER GLOBAL, and this is the decision the
# whole design turns on. A child's numbers are read in its parent's own plane.
# Two cities never share an origin and never need one -- so the captain's *"one
# location might have multiple rooms and floors within it"* and his
# *"connected locations don't necessarily have to be planar distances"* are both
# true BY CONSTRUCTION rather than by convention. There is no global space for
# the non-planar world graph to be inconsistent with, because there is no global
# space. A box is therefore meaningless without a parent, and comparing two
# boxes under different parents is meaningless too: `Location#overlaps?` is the
# reader that knows that, and it refuses the comparison rather than answering it.
#
# `z` IS A STOREY INDEX AND NOT A HEIGHT, which follows from ruling 3: there is
# no vertical extent to be measured, only which plane you are standing on. And
# a child's `z` is read in its PARENT's frame -- which storey of the parent this
# room is on -- while the parent's own `z` is read in the grandparent's. The two
# are different frames and are never compared.
#
# INTEGERS, AND THE UNIT IS THE PACE -- one cell, roughly 1.5 m, which is the
# one place in the app that number is written down and the conversion prose may
# talk in metres by. Integer because OVERLAP MUST BE EXACT: floats invite drift,
# and drift in geometry is a contradiction `Story::Audit` would have to chase
# through the prose rather than a defect a test could catch.
#
# THE INTERVALS ARE HALF-OPEN: a box at x = 0 with width 3 occupies 0, 1 and 2,
# and a box at x = 3 begins where it ends. So TWO ROOMS SHARING A WALL DO NOT
# OVERLAP -- which is what makes a door on a shared wall expressible at all in
# slice 2, and it is why the comparison below is `<` and not `<=`.
#
# THERE ARE TWO WHOLE SHAPES AND NOT ONE, and this is the correction the first
# draft of these columns needed. "A box is all five columns or none" and "a
# position needs a parent to be read in" and "a parent needs a footprint for its
# children to be read against" cannot all three hold at once: the outermost
# place of any interior would need a parent, and so would that one. Something
# has to sit at the top of the tree. So:
#
#   A FOOTPRINT is `width` and `depth` with no position -- *this place has an
#   inside, and it is this big*. It is what the OUTERMOST place of an interior
#   carries. It states an extent and no position, which is exactly right,
#   because coordinates are local to a parent and a place at the top of a
#   containment tree HAS no frame to state a position in. A footprint is the
#   plane its children's positions are read in, and that is the whole of what it
#   is for.
#
#   A BOX is all five -- *and it sits here, on this storey of its parent*. It is
#   what a ROOM carries.
#
# Anything else is PARTIAL and is a defect: two of the three position columns,
# or a position with no extent, or a width with no depth. `Location` refuses
# one, `WorldSeed::Loader` refuses a file that writes one, and
# `Story::Doctor` reports a row a database already carries.
#
# A VALUE OBJECT RATHER THAN A CONCERN ON `Location`, and the justification is
# that overlap is arithmetic between two rectangles and nothing about it wants a
# database row. As a `Data` it is immutable, it compares by value, and its tests
# need no story, no universe and no save -- so the one piece of this programme
# that MUST be exact is the one piece that can be exercised for nothing. What
# stays on `Location` is only what needs a record: `#interior?`, `#box`, and the
# containment `#overlaps?` has to know about.
#
# NOTHING LAYS ONE OUT YET. The engine is the sole author of every one of these
# numbers, on exactly the terms `Character::StatBlock`, `items.bulk` and
# `locations.danger` are already held to -- no model and no typed line writes
# one, which `EngineSweep::Invariants#geometry_unmoved` asserts over a whole
# walk. Today the only writer is a seed file; in slice 2 it is the layout
# generator, rolled through `Roll` so a world's shape is re-derivable for ever.
class Location::Box < Data.define(:x, :y, :z, :width, :depth)
  # HOW BIG A PACE IS, IN METRES, and it is here rather than in a prompt because
  # the engine owns the unit. The floor plan on the map page is the only reader
  # so far, and it only prints it; no model is told it yet -- slice 3 is where
  # `Playthrough::Moment` gets to say "six paces by four" to a narrator. Written
  # down once so that every reader gets the same answer.
  METRES_PER_PACE = 1.5

  # WHERE A ROOM SITS IN ITS PARENT'S PLANE. `z` is a storey index and not a
  # height: 2.5D, so there is no vertical extent to measure.
  POSITION = %w[x y z].freeze

  # HOW BIG IT IS. On its own, with no position, this is a FOOTPRINT -- see the
  # header.
  EXTENT = %w[width depth].freeze

  # The five, in the order a file and a header read them. Named here so the
  # loader, the exporter, the doctor and the sweep invariant all ask one place
  # what a box is made of.
  COLUMNS = (POSITION + EXTENT).freeze

  # WHICH OF THE FOUR SHAPES A ROW IS IN, and the one question every reader of
  # these columns asks. Four answers rather than a pair of predicates because
  # they are exclusive and a reader that asked two questions could be told two
  # things:
  #
  #   :none       no interior. What every row in every database is today.
  #   :footprint  an extent and no position -- the outermost place of an
  #               interior, and the plane its children are read in.
  #   :box        all five -- a room, placed on a storey of its parent.
  #   :partial    anything else, which is a defect. See the header.
  def self.shape(record)
    position = POSITION.count { |column| record[column].present? }
    extent = EXTENT.count { |column| record[column].present? }

    return :none if position.zero? && extent.zero?
    return :footprint if position.zero? && extent == EXTENT.size
    return :box if position == POSITION.size && extent == EXTENT.size

    :partial
  end

  # A box off a record, or NIL when the record is not in the `:box` shape -- a
  # place with a footprint and no position included, because a footprint has
  # nowhere to be and nothing to overlap. Nil rather than a box of nils, so a
  # caller that has a box never has to ask whether its numbers are real.
  def self.of(record)
    return nil unless shape(record) == :box

    new(**COLUMNS.to_h { |column| [ column.to_sym, record[column].to_i ] })
  end

  # WHETHER A ROW SAYS HALF A THING -- neither a footprint, nor a box, nor
  # nothing at all. The rule `Character#a_stat_block_is_whole` holds a body to,
  # for its reason: a row carrying part of an answer is a column set that looks
  # as though it said something and did not.
  def self.partial?(record) = shape(record) == :partial

  # WHETHER THESE TWO BOXES ARE IN THE SAME PLACE AT ONCE. False across storeys
  # before any arithmetic is done, which is ruling 3 stated as code: each floor
  # is its own plane, so a room directly above another shares nothing with it.
  #
  # Half-open on both axes -- see the header. Two rooms that share a wall are
  # touching and not overlapping, and that is the whole point.
  #
  # IT DOES NOT ASK WHOSE CHILDREN THESE ARE, because a box does not know: two
  # boxes under different parents are read in different planes and the question
  # is meaningless. `Location#overlaps?` is the reader that holds that rule.
  def overlaps?(other)
    return false unless z == other.z

    x < other.x + other.width && other.x < x + width &&
      y < other.y + other.depth && other.y < y + depth
  end

  # One phrase, for a doctor finding and a broken invariant -- so the two places
  # that have to describe a box to a person describe it the same way.
  def to_s = "#{width}x#{depth} paces at #{x},#{y} on storey #{z}"
end
