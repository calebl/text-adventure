# WHERE IN A ROOM A THING OR A PERSON IS STANDING -- two numbers, and the
# arithmetic that answers whether they are inside the room they are in.
#
# `Location::Box` IS THE FILE TO READ FIRST. It owns the four rulings of
# 2026-09-06, why coordinates are local to a parent, why a storey is an index
# rather than a height, why the unit is the pace and the arithmetic integer, and
# why a place has TWO whole shapes. This is the same design one level down: a
# box is where a ROOM is, and a spot is where something INSIDE a room is.
#
# IT IS READ IN THE ROOM'S OWN BOX'S FRAME -- the parent's plane, and NOT a
# room-local frame starting at the room's near corner. That is the decision this
# file turns on, and the alternative was real:
#
#   THE PARENT'S PLANE (chosen). A chair in the taproom and a chair in the back
#   room are two numbers in ONE plane, so how far apart they are is
#   arithmetic anybody can do -- `Location::Box#paces_to` already works this way
#   for the rooms themselves, and a later slice that wants a throw distance or a
#   line of sight across a doorway needs no translation. A spot is directly
#   comparable with the box of the room it is in, which is what makes
#   `Location::Box#contains?` a one-line predicate and the doctor's finding
#   exact.
#
#   THE ROOM'S OWN FRAME (rejected). Positions would survive a room being
#   moved, which sounds like an advantage and buys nothing: nothing moves a
#   room. `EngineSweep::Invariants#geometry_unmoved` asserts precisely that a
#   walk does not, and a room is laid out once, ever
#   (`Location::Interior#lay_out!`). What it would cost is a translation on
#   every read -- and a translation whose input is the room's box is a
#   translation that is wrong for every row in a room with no box, which is
#   almost every row there is.
#
# THERE IS NO `z`, because a storey belongs to the ROOM. A thing is in a room
# and the room is on a storey, so asking a chair which floor it is on is asking
# its room. See `20260906130000_a_thing_gets_a_position.rb`.
#
# TWO WHOLE SHAPES AGAIN, and only two: `:none` and `:spot`. A box needed three
# because something has to sit at the top of a containment tree with an extent
# and no position; nothing sits at the top of THIS tree -- a thing is either
# somewhere in a room or it is unplaced -- so one number of the two is
# `:partial` and is a defect, exactly as two of a box's five are.
# `Item#a_position_is_whole` and `Character#a_position_is_whole` refuse one,
# `WorldSeed::Loader#validate_positions!` refuses a file that writes one, and
# `Story::Doctor` reports a row a database already carries.
#
# UNPLACED IS NOT A DEFECT AND IS THE ORDINARY STATE. Every row in every
# database today is unplaced, and so is every row in a room with no box -- the
# three checked-in worlds are flat by the captain's fourth ruling of 2026-09-06,
# so nothing in them has anywhere to be. NULL says so honestly; a zero would put
# a thing in the corner of a plane that does not exist.
#
# A VALUE OBJECT, FOR `Location::Box`'S REASON: whether a spot is inside a
# rectangle is arithmetic between two integers and a rectangle, and nothing
# about it wants a database row. What stays on the records is only what needs
# one -- `Item#position` and `Character#position`, which is the reader a later
# slice calls (see below).
#
# WHO READS IT, AND WHO DOES NOT YET. Nothing in the play path reads a
# coordinate: `Playthrough::Moment` is slice 3's file and is not touched here.
# `Item#position`, `Character#position` and `Location::Box#contains?` are the
# three readers a later slice calls -- what to tell a narrator about where
# something is standing, and how far a thing was thrown -- and they are public
# and tested so that slice needs no new reader.
#
# THE ENGINE IS THE SOLE AUTHOR of both numbers, on `Location::Box`'s own terms
# and for the standing constraint's reason: no model and no typed line writes
# one. There is exactly one writer, `Location::Placement`, and a SEED FILE, and
# there is not meant to be a third.
class Location::Spot < Data.define(:x, :y)
  # THE TWO COLUMNS, in the order a file and a header read them. Named here so
  # the loader, the exporter, the doctor and the sweep invariant all ask one
  # place what a position is made of. It is deliberately the same two names
  # `Location::Box::POSITION` uses for a room's own corner: they are the same
  # question about a different kind of thing, read in the same plane.
  COLUMNS = %w[x y].freeze

  # WHICH OF THE THREE SHAPES A ROW IS IN. Three answers rather than a pair of
  # predicates, for `Location::Box.shape`'s reason: they are exclusive, and a
  # reader that asked two questions could be told two things.
  #
  #   :none     unplaced. What every row in every database is today, and what a
  #             row in a room with no box must be.
  #   :spot     both numbers -- somewhere in the room it is in.
  #   :partial  one of the two, which is a defect. See the header.
  def self.shape(record)
    written = COLUMNS.count { |column| record[column].present? }

    return :none if written.zero?
    return :spot if written == COLUMNS.size

    :partial
  end

  # A spot off a record, or NIL when the record is not in the `:spot` shape.
  # Nil rather than a spot of nils, so a caller that has a spot never has to ask
  # whether its numbers are real -- `Location::Box.of`'s rule.
  def self.of(record)
    return nil unless shape(record) == :spot

    new(**COLUMNS.to_h { |column| [ column.to_sym, record[column].to_i ] })
  end

  # WHETHER A ROW SAYS HALF A THING. `Location::Box.partial?`'s counterpart, and
  # the rule `Character#a_stat_block_is_whole` holds a body to: a row carrying
  # part of an answer is a column set that looks as though it said something and
  # did not.
  def self.partial?(record) = shape(record) == :partial

  # ONE CELL OF A BOX, DRAWN FROM A GENERATOR SOMEBODY ELSE SEEDED. The
  # arithmetic of "inside this rectangle" lives here with the rest of it; WHICH
  # generator, and therefore whether the same thing lands in the same place next
  # week, is `Location::Placement`'s and is the interesting half.
  #
  # TWO DRAWS IN A FIXED ORDER, x then y -- `Roll`'s standing rule, and the one
  # thing here that must not be tidied: a caller throwing several dice for one
  # decision throws them from one seed in one order, or nothing is re-derivable.
  #
  # EVERY CELL IS A CANDIDATE, including the ones against the walls, because a
  # room's box is the floor of the room and its edge is where the wall is -- the
  # intervals are half-open (`Location::Box`), so `x + width` is the wall's cell
  # and is not offered.
  #
  # NO DOOR CELL IS AVOIDED, BECAUSE THERE IS NO DOOR CELL TO AVOID, and this is
  # worth saying out loud because it looks like an omission. A door in this app
  # is an EDGE -- two `LocationConnection` rows between two rooms (the ruling of
  # 2026-09-03) -- and nothing anywhere records WHERE along the shared wall it
  # stands. `Location::Interior` opens a door when two boxes share a run of at
  # least `Location::Box::MINIMUM_DOORWAY`; it picks no cell, so there is no
  # cell to keep clear. When a slice records one, this is the one method that
  # would read it and nothing else changes.
  def self.inside(box, rng:)
    new(x: Roll.one_of(box.x...(box.x + box.width), rng: rng),
        y: Roll.one_of(box.y...(box.y + box.depth), rng: rng))
  end

  # One phrase, for a doctor finding and a broken invariant -- so the two places
  # that have to describe a position to a person describe it the same way.
  # `Location::Box#to_s` reads "7x4 paces at 0,0 on storey 0", and this is the
  # same "at x,y" said on its own.
  def to_s = "at #{x},#{y}"
end
