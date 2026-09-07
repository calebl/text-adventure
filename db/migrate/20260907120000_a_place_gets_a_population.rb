# HOW POPULATED A PLACE IS, AS A COLUMN. The captain's ruling of 2026-09-07 --
# *"The narrarator should get to decide how populated a room should be"*, by a
# closed-list pick -- and this is where the pick is kept.
#
# `Location::Population` owns the labels, the bands and the rolls, and its
# header is the design; what belongs here is why the column has the shape it
# has.
#
# ONE NULLABLE STRING, NO DEFAULT AND NO BACKFILL, which is
# `20260906120000`'s answer for a box and `20260906130000`'s for a position, for
# the same reason: NULL is not a missing value, it is a real state with a
# defined meaning -- *nobody picked a word for this room* -- and the engine
# rolls one at realization out of `Location::Population::ROLLED`. Every stub in
# every database today is honestly in that state, and so are three kinds of room
# this app will go on making for ever: the opening room, a room of a laid-out
# interior, and a seeded room whose file leaves the key out. So `bin/update`
# gains no step (`lib/update.rb`) -- there is nothing about an existing database
# that is wrong.
#
# IT IS NOT `locations.danger`'s SHAPE, and the difference is the point.
# `danger` is `null: false` with a default, because every room HAS a danger and
# `Location::SAFE` is what a room nobody said anything about is. A population
# label is not like that: "nobody" is a word a model or a world file CHOSE,
# and it has to be tellable apart from nobody having chosen at all -- the first
# is a decision the engine honours, the second is a decision the engine makes.
# A `default: "nobody"` would erase that difference and give every legacy stub
# an empty room somebody appeared to have asked for.
#
# NO INDEX. Nothing filters on it: the column is read one row at a time, by the
# room being realized, at the moment its cast is rolled. An index nothing
# queries is a write cost with no reader -- `20260906130000`'s reasoning.
class APlaceGetsAPopulation < ActiveRecord::Migration[8.1]
  def change
    add_column :locations, :population, :string
  end
end
