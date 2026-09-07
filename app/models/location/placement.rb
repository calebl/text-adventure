# THE ONE THING THAT DECIDES WHERE IN A ROOM SOMETHING GOES. Every `items.x`,
# `items.y`, `characters.x` and `characters.y` the app ever writes is a hash out
# of this file, and a SEED FILE is the only other author there is.
#
# THE STANDING CONSTRAINT, APPLIED ONE LEVEL DOWN. A model may name what is in
# a room -- `Location::DetailSchema` has an `items` array and a cast -- and it
# may not say where any of it is. There is no field for a coordinate in any
# schema in the app, nothing in any prompt mentions one, and this class is a
# `Roll` and some arithmetic with no model call anywhere in it. So a position
# cannot be wrong in the way a narrated one could: the engine gates the state
# and a later slice informs the prose (`Playthrough::Moment`, slice 3).
# `EngineSweep::Invariants#geometry_unmoved` already asserts the same sentence
# about a room's own five columns, and `#positions_in_bounds` asserts this one.
#
# --- the two statements, and why they are two --------------------------------
#
# `.in_the_world` and `.in_a_game` are the layer split said as a placement, and
# the difference between them is WHAT THE ROLL'S IDENTITY IS:
#
#   IN THE WORLD -- an `Item` template written by `Item::Registry` at
#   realization, a `Character` written or moved by `Character::Registry`, a
#   person walked somewhere by `Character#move_to!`. The identity is the ROW and
#   nothing else: `playthrough: 0` and `at: 0`, which is `Location::Interior`'s
#   choice for an interior and its reason -- world data is re-derivable for
#   ever, so the durable thing about a chair is which chair it is. The same row
#   put in the same room twice therefore lands in the SAME cell, which is
#   correct rather than a coincidence: a re-seed puts the world's own daybook
#   back on the same shelf, and a clerk who leaves a room and comes back stands
#   where he was standing.
#
#   IN A GAME -- one playthrough's own copy, set down by
#   `Playthrough::Turn#put_down!` (a drop, or a throw through a doorway) or
#   spilled by `#spill!`. The identity is the row AND the moment: which game,
#   and where the STORY's clock stood, which is `Playthrough::Turn#strike!`'s own
#   seed shape. So dropping the same thing again later puts it somewhere else,
#   which is what a person watching a floor would expect; dropping it twice
#   inside one fight -- which does not advance the clock (`Playthrough::Fight`)
#   -- puts it back in the same place, and that is the same thing landing in the
#   same spot rather than a defect.
#
# THE ROW'S ID IS THE SEQUENCE, WHICH MAKES A PLACEMENT A SECOND WRITE for
# anything being created. `Item::Registry` and `Character::Registry` create the
# row and then place it, exactly as `Location::Interior#create_room!` writes a
# stub and then its box, and for a stronger version of the same reason: an id is
# the only identity a new row has that is unique, durable and an integer, and
# `Roll` takes nothing but integers (see its header for why `String#hash` is not
# one). The alternatives were both worse:
#
#   the row's NAME     not an integer. `String#hash` is salted per process, so
#                      seeding from a name would move every position after a
#                      restart -- the exact property `Roll` exists to have.
#   its ORDINAL in
#   the call           re-derivable only until the room gains another thing.
#                      `Location::Danger` can key on a count because it rolls
#                      once at birth and never again; a position is re-derived
#                      by anybody asking where the chair was, for ever.
#
# --- what happens when there is nowhere to be --------------------------------
#
# A ROOM WITH NO BOX PLACES NOTHING, and that is the ordinary case rather than
# the corner. A position is read in a room's own plane (`Location::Spot`) and a
# room with no box opens none, so there is no cell to pick and the honest answer
# is both columns nil. Every row in every database is in that state today and
# the three checked-in worlds are entirely in it (the captain's fourth ruling of
# 2026-09-06). NIL rather than a zero, because a zero is a corner of a plane
# that does not exist.
#
# IT ALWAYS ANSWERS WITH BOTH COLUMNS, never one and never none of them, so
# every caller writes a whole position or a whole nothing in one statement --
# which is what `Item#a_position_is_whole` and `Character#a_position_is_whole`
# refuse the alternative of. It is also what makes a MOVE correct without any
# caller remembering: a person walked out of a laid-out building into a flat
# street is handed `{ x: nil, y: nil }` and stops being anywhere in particular.
class Location::Placement
  # WHICH `Roll` AXIS A ROW'S POSITION IS DRAWN ON, by table. Item ids and
  # character ids collide freely, so the axis is what tells a chair from a clerk
  # -- see `Roll::ITEM_POSITION`.
  #
  # ON THE MODEL NAME rather than on a method the record answers, because the
  # answer has to be the same for both halves of the item layer split: a
  # template and one playthrough's copy of it are both `Item` and are both
  # placed on the same axis.
  KINDS = { "Item" => Roll::ITEM_POSITION, "Character" => Roll::CHARACTER_POSITION }.freeze

  # WHERE THE WORLD PUTS THIS ROW IN THIS ROOM. See the header for why the seed
  # is the row and nothing else.
  def self.in_the_world(room, record)
    spot(room, record)
  end

  # WHERE ONE GAME PUTS THIS ROW IN THIS ROOM, at the moment its own story clock
  # stands. `Playthrough#story_now` is the clock a turn reads everywhere else.
  def self.in_a_game(room, record, playthrough:)
    spot(room, record, playthrough: playthrough&.id.to_i, at: playthrough&.story_now.to_i)
  end

  # NOWHERE IN PARTICULAR, as a pair of columns. It is a named statement rather
  # than a literal at three call sites because "this row has no position" is a
  # decision -- an item in a pair of hands has no room to be read in, and a row
  # walked out of a laid-out place stops being anywhere -- and a caller that
  # spelt the pair out could spell half of it.
  def self.unplaced = { x: nil, y: nil }

  # THE ONE GENERATOR, AND THE ONE PLACE A POSITION'S SEED IS BUILT. Private
  # because the two public statements above are the whole vocabulary: a caller
  # picking its own `at` would be a caller inventing a fourth layer.
  def self.spot(room, record, playthrough: 0, at: 0)
    box = room&.box
    return unplaced if box.nil?

    rng = Roll.generator(story: room.story_id, playthrough: playthrough, at: at,
                         sequence: record.id.to_i, kind: kind_for(record))

    Location::Spot.inside(box, rng: rng).to_h
  end
  private_class_method :spot

  # THE AXIS FOR THIS ROW'S TABLE. It RAISES on anything else rather than
  # falling back to `0`: kind zero is the axis every roll thrown before kinds
  # existed shares (`Roll`), so a third table quietly placed on it would seed
  # its positions identically to a stat block's. A new table gets a new kind,
  # and the failure that says so is this line.
  def self.kind_for(record)
    KINDS.fetch(record.class.base_class.name) do
      raise ArgumentError, "#{record.class.name} has no position axis; #{KINDS.keys.join(" and ")} do"
    end
  end
  private_class_method :kind_for
end
