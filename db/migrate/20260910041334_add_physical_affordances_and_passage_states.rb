class AddPhysicalAffordancesAndPassageStates < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :use_kind, :string, null: false, default: "ordinary"
    add_column :items, :combustible, :boolean, null: false, default: false
    add_column :items, :disposition, :string, null: false, default: "intact"

    add_column :location_connections, :barrier, :string, null: false, default: "open"
    add_reference :location_connections, :key_template,
                  foreign_key: { to_table: :items, on_delete: :nullify }

    create_table :playthrough_passages do |t|
      t.references :playthrough, null: false, foreign_key: { on_delete: :cascade }
      t.references :location_connection, null: false, foreign_key: { on_delete: :cascade }
      t.references :opened_by_item, foreign_key: { to_table: :items, on_delete: :nullify }
      t.string :means, null: false
      t.datetime :opened_at, null: false
      t.timestamps
    end
    add_index :playthrough_passages, [ :playthrough_id, :location_connection_id ], unique: true
  end
end
