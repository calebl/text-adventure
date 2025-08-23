class CreateCharacters < ActiveRecord::Migration[8.0]
  def change
    create_table :characters do |t|
      t.references :story, null: false, foreign_key: true
      t.string :fullname
      t.string :nickname
      t.integer :age
      t.string :sex
      t.string :race
      t.text :personality
      t.text :appearance
      t.text :likes
      t.text :dislikes
      t.text :fears
      t.text :backstory
      t.boolean :is_companion

      t.timestamps
    end
  end
end
