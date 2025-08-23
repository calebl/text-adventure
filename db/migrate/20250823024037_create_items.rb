class CreateItems < ActiveRecord::Migration[8.0]
  def change
    create_table :items do |t|
      t.references :character, null: false, foreign_key: true
      t.string :name
      t.text :description
      t.text :properties

      t.timestamps
    end
  end
end
