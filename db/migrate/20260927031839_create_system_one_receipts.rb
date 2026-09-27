class CreateSystemOneReceipts < ActiveRecord::Migration[8.1]
  def change
    create_table :system_one_receipts do |t|
      t.references :player, null: true, foreign_key: true
      t.references :playthrough, null: true, foreign_key: true
      t.string :purpose
      t.string :transport
      t.decimal :cost_usd, precision: 12, scale: 6, null: false
      t.timestamps
    end
    add_index :system_one_receipts, [ :player_id, :created_at ]
  end
end
