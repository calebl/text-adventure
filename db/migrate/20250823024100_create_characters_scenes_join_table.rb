class CreateCharactersScenesJoinTable < ActiveRecord::Migration[8.0]
  def change
    create_join_table :characters, :scenes do |t|
      t.index [ :character_id, :scene_id ]
      t.index [ :scene_id, :character_id ]
    end
  end
end
