class AddNpcAgencyToPlaythroughs < ActiveRecord::Migration[8.1]
  def change
    create_table :playthrough_npc_states do |t|
      t.references :playthrough, null: false, foreign_key: true
      t.references :character, null: false, foreign_key: true
      t.references :location, foreign_key: true
      t.boolean :following, null: false, default: false
      t.boolean :ceasefire, null: false, default: false
      t.integer :peace_after_blow_id, null: false, default: 0
      t.timestamps
    end
    add_index :playthrough_npc_states, [ :playthrough_id, :character_id ], unique: true

    add_column :interactions, :engine_action, :string
    add_column :interactions, :action_status, :string
    add_column :interactions, :action_fact, :text
  end
end
