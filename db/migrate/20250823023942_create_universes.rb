class CreateUniverses < ActiveRecord::Migration[8.0]
  def change
    create_table :universes do |t|
      t.text :physics
      t.text :technology
      t.text :weapons
      t.text :races
      t.text :civilizations
      t.text :geographies
      t.text :history
      t.text :economics
      t.text :politics
      t.text :religion

      t.timestamps
    end
  end
end
