# One place per name in a story, whatever its case. `Location::Generator`
# looks a name up before it creates a stub, and nothing stopped two
# realizations that both missed from each creating one; this does.
class AddUniqueNameIndexToLocations < ActiveRecord::Migration[8.1]
  def change
    add_index :locations, "story_id, lower(name)", unique: true, name: "index_locations_on_story_id_and_lower_name"
  end
end
