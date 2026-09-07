# A THING AND A PERSON GET A PLACE IN THE ROOM, and it is the fourth slice of
# the coordinates programme.
#
# The captain's design words, 2026-09-06: *"locations having an interior where
# items, characters and exits are placed"*. Slice 1 gave a place its shape and
# slice 2 divided the inside of one into rooms; this is the half of that
# sentence about what is standing in them.
#
# TWO NULLABLE INTEGERS ON EACH OF TWO TABLES, read in the frame the room's own
# box is read in -- its parent's plane, because coordinates are local to a
# parent and there is no global space (`Location::Box`). `Location::Spot` owns
# what a position IS and `Location::Placement` is the one thing that writes one;
# neither is repeated here.
#
# THERE IS NO `z`, and its absence is the design rather than an omission. A
# storey is a property of the ROOM (2.5D, the captain's third ruling of
# 2026-09-06) and a thing is in a room, so the storey a chair is on is the
# storey of the room the chair is in. A `z` on `items` would be a second record
# of that fact and the two could disagree.
#
# BOTH ITEM LAYERS GET THE COLUMNS, because they are one table:
# `playthrough_id` says which layer a row is in, and the captain's ruling of
# 2026-09-04 -- *"If a location is generated with items in it, that should
# become the initial snapshot that any playthrough uses"* -- is exactly a
# statement about a position surviving the copy. `Item::Snapshot` brings it
# along, and from then on the playthrough's own copy moves on its own.
#
# NULLABLE, NO DEFAULT AND NO BACKFILL -- the answer `20260906120000` gave for a
# box, for the same reason. NULL means UNPLACED, which is the honest state of
# every row in every database today and of every row in a room with no box at
# all: a position is read in a room's plane, and a room with no box opens none.
# A zero would be a corner of a plane that does not exist. So `bin/update` gains
# no step -- there is nothing about an existing database that is wrong.
#
# NO INDEX, deliberately, on `20260906120000`'s reasoning: the only queries
# these columns answer are "this row's own two numbers" and "the positioned rows
# of one story", and the second is a diagnostic (`Story::Doctor`,
# `EngineSweep::Invariants`) that already scans the story's rows through the
# indexes on `location_id`. An index nothing filters on is a write cost with no
# reader.
class AThingGetsAPosition < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :x, :integer
    add_column :items, :y, :integer
    add_column :characters, :x, :integer
    add_column :characters, :y, :integer
  end
end
