class CreatePlaythroughTurnEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :playthrough_turn_events do |t|
      t.references :playthrough_command, null: false, foreign_key: true
      t.integer :sequence, null: false
      t.string :kind, null: false
      t.json :data, null: false, default: {}
      t.timestamps
    end
    add_index :playthrough_turn_events, [ :playthrough_command_id, :sequence ], unique: true,
              name: "index_playthrough_turn_events_on_command_and_sequence"
  end
end
