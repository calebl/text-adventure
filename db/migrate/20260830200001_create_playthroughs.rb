class CreatePlaythroughs < ActiveRecord::Migration[8.1]
  def change
    create_table :playthroughs do |t|
      t.references :story, null: false, foreign_key: true
      # A playthrough exists before the player has picked a character or been
      # placed anywhere, so everything but the story is optional.
      t.references :character, foreign_key: true
      t.references :current_location, foreign_key: { to_table: :locations }
      t.references :current_scene, foreign_key: { to_table: :scenes }
      t.string :token, null: false

      t.timestamps
    end

    add_index :playthroughs, :token, unique: true
  end
end
