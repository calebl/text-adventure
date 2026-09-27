class CreatePlayers < ActiveRecord::Migration[8.1]
  def change
    create_table :players do |t|
      t.string :name, null: false
      t.string :token_digest, null: false
      t.decimal :monthly_limit_usd, precision: 10, scale: 4, null: false, default: 1
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :players, :name, unique: true
    add_index :players, :token_digest, unique: true
  end
end
