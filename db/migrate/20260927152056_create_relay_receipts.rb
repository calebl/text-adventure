class CreateRelayReceipts < ActiveRecord::Migration[8.1]
  def change
    create_table :relay_receipts do |t|
      t.references :player, null: false, foreign_key: true
      t.string :route, null: false
      t.string :model, null: false
      t.boolean :stream, null: false, default: false
      t.string :status, null: false, default: "open"
      t.decimal :reserved_usd, precision: 12, scale: 6, null: false
      t.decimal :cost_usd, precision: 12, scale: 6
      t.string :cost_source
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :upstream_status
      t.datetime :finished_at
      t.timestamps
    end
    add_index :relay_receipts, [ :player_id, :created_at ]
    add_index :relay_receipts, [ :player_id, :status ]
  end
end
