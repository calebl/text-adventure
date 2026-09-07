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
# THE ENGINE IS THE SOLE AUTHOR of every one of these numbers, on exactly the
# terms `Character::StatBlock`, `items.bulk` and `locations.danger` are already
# held to -- no model and no typed line writes one, which
# `EngineSweep::Invariants#geometry_unmoved` asserts over a whole walk. There
# are two writers and there is not meant to be a third: a SEED FILE, and
# `Location::Interior`, which lays a whole interior out from one seeded `Roll`
# so a world's shape is re-derivable for ever.
class Location::Box < Data.define(:x, :y, :z, :width, :depth)
  # HOW BIG A PACE IS, IN METRES, and it is here rather than in a prompt because
  # the engine owns the unit. The floor plan on the map page prints it and
  # `Location::Plan` is what finally says "six paces by four" to a model, in
  # paces and in metres off this one number. Written down once so that every
  # reader gets the same answer.
  METRES_PER_PACE = 1.5

  # HOW SHORT A SHARED WALL MAY BE AND STILL HOLD A DOOR. One pace: a doorway is
  # a person wide, so two rooms meeting only at a corner share no wall at all.
  MINIMUM_DOORWAY = 1

  # WHICH WAY IS WHICH, and it is a decision rather than a discovery: nothing in
  # the records says where north is, so the engine says it here and says it
  # once. NORTH IS UP ON THE FLOOR PLAN `Story::Map` DRAWS -- x rises to the
  # EAST and y rises to the SOUTH, which is a plan drawn the way every plan is
  # drawn and the way the page already renders one (SVG's y runs down the
  # screen). A room at a greater `y` than its neighbour is therefore south of
  # it, and `#wall_towards` is the only place that reading is made.
  #
  # IT IS A NAME FOR A SIDE AND NOT A CLAIM ABOUT THE WORLD. Coordinates are
  # local to a parent (see the header), so "north" means "the top of this
  # building's own plan" and two buildings share no compass any more than they
  # share an origin. Nothing compares one place's north with another's.
  NORTH = "north".freeze
  EAST = "east".freeze
  SOUTH = "south".freeze
  WEST = "west".freeze

  # The four, in the order a compass is read out. Named so a reader that has to
  # list or sort walls asks one place what they are.
  WALLS = [ NORTH, EAST, SOUTH, WEST ].freeze

  # HOW FAR OFF CENTRE A PART OF A ROOM HAS TO LIE BEFORE IT IS WORTH A COMPASS
  # WORD: a quarter of the room's own side, on that axis. It is the one number
  # in `#bearing_of` and it is here because the alternative is worse in both
  # directions -- with no floor at all a stairwell half a pace off centre in a
  # seven-pace room would be reported as "in the west of the room", which is a
  # precision the records do not have; with a floor set high nothing would ever
  # earn a word and the answer would always be silence.
  #
  # A QUARTER RATHER THAN A HALF because a bearing is read against the room's
  # CENTRE and not against its far wall: a part whose own centre stands a
  # quarter of the way out is a part sitting plainly in that end of the room.
  BEARING_SHARE = 4

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

    shares_ground?(other)
  end

  # THE SAME QUESTION WITH THE STOREY TAKEN OUT: whether these two rooms would
  # be in the same place if they were on one floor. It is `#overlaps?` minus its
  # first line, and it exists because a STAIR is the one edge that is read
  # across storeys: floors are kept aligned (ruling 3), which means a stairwell
  # at (x, y) on one storey arrives at (x, y) on the next -- and the whole of
  # what "aligned" means is that the two rooms a stair joins have a point in
  # common when the storeys are ignored.
  #
  # THERE IS NO STAIRWELL RECORD and there does not need to be one: the
  # alignment IS the record. Two boxes and this predicate answer it, so nothing
  # has to keep a point in a column that could disagree with the rooms it
  # names. `Location::Interior` builds every stair to satisfy this and
  # `Story::Doctor` reports a pair that does not.
  #
  # `#shared_ground` IS THE STATEMENT AND THIS IS THE QUESTION, the way
  # `#shares_a_wall?` and `#shared_wall` are one rule below. It matters more
  # here than there: `Location::Interior` builds stairs to satisfy the
  # PREDICATE while `Location::Plan#way_for` reads the REGION, so two
  # statements of where a stairwell can be would eventually put a bearing on a
  # stair the layout thinks impossible, or none on one it built.
  def shares_ground?(other) = !shared_ground(other).nil?

  # WHETHER A DOOR COULD OPEN BETWEEN THESE TWO: same storey, touching walls,
  # and touching along enough of them for a doorway to stand in. Half-open
  # intervals are what make this expressible at all -- two rooms sharing a wall
  # do not overlap, so `#overlaps?` is false for exactly the pairs this is true
  # of (see the header).
  #
  # THE SHARED RUN HAS TO BE AT LEAST `MINIMUM_DOORWAY`, because rooms that meet
  # at a CORNER touch on both axes and share no wall at all: the run between
  # them is zero paces long and a door there would be a door through a corner.
  # `#shared_wall` is where that arithmetic is, and this is the predicate form of
  # it -- one rule, asked as a question or asked for the wall.
  def shares_a_wall?(other) = !shared_wall(other).nil?

  # THE WALL ITSELF: the axis it stands on, the coordinate it stands at, and the
  # stretch of it the two rooms have in common -- or nil when they do not touch,
  # or touch at a corner alone. `:x` is a wall running north to south at that
  # `x`; `:y` is one running east to west.
  #
  # IT MOVED HERE FROM `Story::Map`, which is where it was written and which
  # said in its own header that this is where it belongs: *"a value object gains
  # a method when something in the engine needs it"*. Slice 3 is that moment --
  # `Location::Plan` has to tell a model WHICH WALL a door is in, which is this
  # arithmetic and not pixels -- so the map now calls this and owns only the
  # drawing. One statement of where a door can stand, for the picture and for
  # the prompt.
  #
  # THE STOREY IS PART OF IT. Each floor is its own plane (ruling 3), so two
  # rooms on different storeys share no wall however their outlines lie.
  def shared_wall(other)
    return nil unless z == other.z

    if touching?(x, width, other.x, other.width)
      along = span(y, depth, other.y, other.depth)
      return [ :x, x + width == other.x ? x + width : other.x + other.width, *along ] if wide_enough?(along)
    elsif touching?(y, depth, other.y, other.depth)
      along = span(x, width, other.x, other.width)
      return [ :y, y + depth == other.y ? y + depth : other.y + other.depth, *along ] if wide_enough?(along)
    end

    nil
  end

  # WHICH OF THIS ROOM'S FOUR WALLS THE DOOR TO `other` IS IN, or nil when no
  # door could stand between them. Read in the parent's own plane and named by
  # the convention at the top of this class -- and it is asked of THIS box, so
  # the same doorway is the east wall of one room and the west wall of the
  # other, which is what a person walking through it experiences.
  def wall_towards(other)
    wall = shared_wall(other)
    return nil if wall.nil?

    if wall.first == :x
      x + width == other.x ? EAST : WEST
    else
      y + depth == other.y ? SOUTH : NORTH
    end
  end

  # WHERE TWO ROOMS ON DIFFERENT STOREYS STAND OVER EACH OTHER, as a box on THIS
  # one's storey -- or nil when they do not. `#shares_ground?` asked for the
  # region rather than the answer.
  #
  # IT IS WHAT THE RECORDS KNOW ABOUT WHERE A STAIRWELL IS. There is no
  # stairwell record and there does not need to be one (see `#shares_ground?`):
  # a stair joins two rooms only where they stand over each other, so the
  # stairwell can only be inside this rectangle. Anything said about where the
  # stairs are in a room is said about this and never invented.
  def shared_ground(other)
    left, right = span(x, width, other.x, other.width)
    top, bottom = span(y, depth, other.y, other.depth)
    return nil unless right > left && bottom > top

    self.class.new(x: left, y: top, z: z, width: right - left, depth: bottom - top)
  end

  # WHICH END OF THIS ROOM A PART OF IT LIES IN -- "north-west", "south", or NIL
  # for a part sitting square in the middle or filling the room. See
  # `BEARING_SHARE` for the floor and why there is one.
  #
  # DOUBLED ARITHMETIC, so it stays integer for the reason `#paces_to` does: a
  # room an odd number of paces across has its centre on a half pace.
  def bearing_of(part)
    words = [ offset_word(2 * part.y + part.depth - (2 * y + depth), depth, NORTH, SOUTH),
              offset_word(2 * part.x + part.width - (2 * x + width), width, WEST, EAST) ]

    words.compact.join("-").presence
  end

  # THIS ROOM IN METRES, off the one conversion the engine owns. Rounded to
  # whole metres: a pace is already an approximation of a stride, and a room
  # reported to the decimetre would be claiming a precision `METRES_PER_PACE`
  # does not have.
  def metres = [ in_metres(width), in_metres(depth) ]

  # WHETHER THIS ROOM FITS IN THE PLANE IT IS READ IN. A footprint states an
  # extent and no position (see the header), so its own plane runs from the
  # origin to `width` by `depth` and a room outside that is a room outside the
  # building it is a room of. Half-open again: a room ending exactly at the far
  # wall is inside.
  def inside_footprint?(footprint_width, footprint_depth)
    x >= 0 && y >= 0 &&
      x + width <= footprint_width.to_i && y + depth <= footprint_depth.to_i
  end

  # WHETHER THIS SPOT IS ON THIS ROOM'S FLOOR -- the predicate a positioned
  # `Item` or `Character` is held to, and the one `Story::Doctor` and
  # `EngineSweep::Invariants` both ask.
  #
  # ONE FRAME AND NO TRANSLATION: a spot is read in the same plane a box is, so
  # this is four comparisons and not a coordinate change. `Location::Spot`'s
  # header has the decision and the alternative it was chosen over.
  #
  # HALF-OPEN, like everything else here (see the header): a room at x = 0 with
  # width 3 holds a thing at 0, 1 and 2, and a thing at 3 is in the room next
  # door. So two rooms sharing a wall never both contain one thing, which is
  # what makes "outside its room" an exact fault rather than an off-by-one
  # argument.
  #
  # NIL IS FALSE AND NOT AN ERROR: a row with no position is nowhere, and
  # nowhere is inside nothing. That is `Location#overlaps?`'s answer for an
  # unplaced room and it is right here for the same reason -- the callers sweep
  # every row in a story and would otherwise have to filter before they could
  # ask.
  def contains?(spot)
    return false if spot.nil?

    spot.x >= x && spot.x < x + width &&
      spot.y >= y && spot.y < y + depth
  end

  # HOW FAR APART THESE TWO ARE, IN PACES, measured centre to centre and by the
  # streets rather than through the wall -- a person walks around the furniture,
  # not diagonally through it.
  #
  # THE STOREY IS NOT IN IT, because a storey index is not a height (see the
  # header) and there is no number of paces a floor is worth. What a stair costs
  # is its `travel_method`, which is where the app already keeps the cost of
  # going up (`LocationConnection::TRAVEL_METHODS`).
  #
  # THE ARITHMETIC IS DOUBLED so it stays integer: a room an odd number of paces
  # across has its centre on a half pace, and the halves are dropped at the end.
  # They cannot change the answer any caller wants, because a distance is read
  # as one of `LocationConnection::DISTANCES`' buckets and never as a
  # measurement.
  def paces_to(other)
    (((2 * x + width) - (2 * other.x + other.width)).abs +
      ((2 * y + depth) - (2 * other.y + other.depth)).abs) / 2
  end

  # One phrase, for a doctor finding and a broken invariant -- so the two places
  # that have to describe a box to a person describe it the same way.
  def to_s = "#{width}x#{depth} paces at #{x},#{y} on storey #{z}"

  private

  # Whether two intervals on one axis meet end to end -- one begins exactly
  # where the other stops. Half-open, so this is "touching" and never
  # "overlapping".
  def touching?(start, extent, other_start, other_extent)
    start + extent == other_start || other_start + other_extent == start
  end

  # What two intervals on one axis have in common, as the pair of coordinates it
  # runs between. Empty when the second is not greater than the first, which is
  # the one test every caller here makes of it.
  def span(start, extent, other_start, other_extent)
    [ [ start, other_start ].max, [ start + extent, other_start + other_extent ].min ]
  end

  # Whether a stretch two rooms share is long enough for a doorway to stand in
  # it -- `MINIMUM_DOORWAY`, which is what makes a corner a corner.
  def wide_enough?(span) = span.last - span.first >= MINIMUM_DOORWAY

  # One axis of a bearing: the word for which side of centre `doubled` falls on,
  # or nil when it is not far enough off centre to have a side. See
  # `BEARING_SHARE`.
  def offset_word(doubled, extent, before, after)
    return nil if BEARING_SHARE * doubled.abs < 2 * extent

    doubled.negative? ? before : after
  end

  def in_metres(paces) = (paces * METRES_PER_PACE).round
end
