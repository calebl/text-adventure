# A PLACE GETS A SHAPE, AND IT IS THE FIRST SLICE OF THE COORDINATES PROGRAMME.
#
# The captain's design words, 2026-09-06: *"I want to explore creating a
# coordinates system; locations having an interior where items, characters and
# exits are placed; the map should expand in a realistic 3d way at least within
# a certain scope; one location might have multiple rooms and floors within it,
# these should all connect to one another realistically and occupy set
# dimensions; connected locations don't necessarily have to be planar distances,
# there should be an ability to travel directly from 1 city to another city."*
#
# Five nullable integers on `locations`, all RELATIVE TO `parent_location`:
#
#   x, y     where this room's near corner sits in its parent's own plane
#   z        WHICH STOREY OF THE PARENT it is on -- an index, not a height
#   width    how far it runs along x
#   depth    how far it runs along y
#
# THE UNIT IS THE PACE and the arithmetic is integer. `Location::Box` owns both
# and says why; nothing here repeats it.
#
# ALL FIVE ARE NULLABLE, THERE IS NO DEFAULT AND THERE IS NO BACKFILL, which is
# the answer `locations.hazard` gave one migration back and it is right here for
# the same reason. A danger is a SHARE of a die -- every room has one and `safe`
# is the honest zero. A box is a SHAPE A PLACE HAS, and no place written before
# today has one: NULL on all five says "no interior", which is true of every row
# in every database and of the three checked-in worlds, which the captain's
# fourth ruling of 2026-09-06 leaves flat on purpose. A zero-width default would
# be inventing a floor plan for rooms nobody laid out. So `bin/update` gains no
# step -- there is nothing about an existing database that is wrong.
#
# NO INDEX, deliberately. The only queries these columns answer are "the
# children of one parent" and "this row's own five numbers", and
# `index_locations_on_parent_location_id` already serves the first. An index on
# a column set that nothing filters on is a write cost with no reader.
class ALocationGetsABox < ActiveRecord::Migration[8.1]
  def change
    add_column :locations, :x, :integer
    add_column :locations, :y, :integer
    add_column :locations, :z, :integer
    add_column :locations, :width, :integer
    add_column :locations, :depth, :integer
  end
end
