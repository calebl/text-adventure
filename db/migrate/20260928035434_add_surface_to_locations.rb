# WHAT A ROOM'S FLOOR DOES TO A THING THAT LANDS ON IT: `Location::SURFACES`,
# the rows of `surface` in the Rust engine's `data/physics.yml`, each a number
# added to the share a fragile thing breaks on.
#
# NULLABLE, because nil is a floor that adds nothing, which is every room
# already written: the column is inert until a world names a surface.
class AddSurfaceToLocations < ActiveRecord::Migration[8.1]
  def change
    add_column :locations, :surface, :string
  end
end
