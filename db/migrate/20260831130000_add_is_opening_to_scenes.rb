class AddIsOpeningToScenes < ActiveRecord::Migration[8.1]
  # The story's opening arrival is part of the world, not part of somebody's
  # progress through it: it is generated once when the world is built, carried
  # in db/seeds/worlds/*.yml, and every playthrough of that story starts on it.
  # A Scene has no natural key of its own, so this flag is the one the seed
  # loader matches on -- exactly one per story, which Scene validates.
  def change
    add_column :scenes, :is_opening, :boolean, null: false, default: false

    # Looked up by story (Story#opening_scene), never by the flag alone.
    add_index :scenes, [ :story_id, :is_opening ]
  end
end
