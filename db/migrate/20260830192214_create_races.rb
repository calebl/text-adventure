class CreateRaces < ActiveRecord::Migration[8.0]
  def change
    create_table :races do |t|
      t.references :universe, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description, null: false

      t.timestamps
    end

    add_index :races, [ :universe_id, :name ], unique: true

    # The prose overview is superseded by the individual race records, which
    # carry the same information in a form characters can actually be assigned
    # from. Dropping it also frees the `races` name for the association.
    remove_column :universes, :races, :text
  end
end
