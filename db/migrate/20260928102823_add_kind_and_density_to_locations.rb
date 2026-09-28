# WHAT SORT OF PLACE A ROOM IS, AND HOW MUCH SMALL STUFF LIES ABOUT IN IT, AS
# TWO COLUMNS. `Location::Kind` owns both closed lists and the table a
# building's rooms are dealt their words from; its header is the design, and
# what belongs here is why the columns have the shape they have.
#
# TWO NULLABLE STRINGS, NO DEFAULT AND NO BACKFILL, which is
# `20260907140000`'s answer for `population` and for the same reason: NULL is
# a real state and not a missing value -- *nobody picked a word for this room*
# -- and every row in every database today is honestly in it. So are three
# kinds of room this app will go on making: the opening room, a seeded room
# whose file leaves the key out, and a room of a building whose place call
# picked no sort of building. So `bin/update` gains no step (`lib/update.rb`):
# nothing about an existing database is wrong.
#
# NOTHING READS EITHER COLUMN YET. They are written when a stub is born and
# kept, so the words are on the rows before anything is built on them; a world
# supplies parameters, never behaviour, and a parameter ships inert.
#
# NO INDEX. Nothing filters on either: each is read one row at a time, by the
# room it describes.
class AddKindAndDensityToLocations < ActiveRecord::Migration[8.1]
  def change
    add_column :locations, :kind, :string
    add_column :locations, :density, :string
  end
end
