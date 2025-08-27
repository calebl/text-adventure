class CreateLocations < ActiveRecord::Migration[8.0]
  def change
    create_table :locations do |t|
      t.references :story, null: false, foreign_key: true
      t.string :name
      t.text :description
      t.text :lore
      t.datetime :last_protagonist_visit
      t.references :parent_location, null: true, foreign_key: { to_table: :locations }

      t.timestamps
    end
  end
end
