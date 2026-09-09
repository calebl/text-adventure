class AddTurnCommandsAndEngineFallbacks < ActiveRecord::Migration[8.1]
  def change
    create_table :playthrough_commands do |t|
      t.references :playthrough, null: false, foreign_key: true
      t.string :request_token, null: false
      t.text :command, null: false
      t.string :status, null: false, default: "pending"
      t.references :result_scene, foreign_key: { to_table: :scenes }
      t.json :refusal, null: false, default: {}
      t.string :error_kind
      t.timestamps
    end
    add_index :playthrough_commands, [ :playthrough_id, :request_token, :command ],
              unique: true, name: "index_playthrough_commands_on_submission"
    add_column :scenes, :engine_fallback, :boolean, null: false, default: false
  end
end
