class AddIsProtagonistToCharacters < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :is_protagonist, :boolean, null: false, default: false

    # The player's character is looked up by story, so index the pair rather
    # than the flag alone.
    add_index :characters, [ :story_id, :is_protagonist ]
  end
end
