class CreateScenes < ActiveRecord::Migration[8.0]
  def change
    create_table :scenes do |t|
      t.references :story, null: false, foreign_key: true
      t.references :location, null: false, foreign_key: true
      t.references :previous_scene, null: true, foreign_key: { to_table: :scenes }
      t.text :description
      t.datetime :story_timestamp
      t.text :summary

      t.timestamps
    end
  end
end
