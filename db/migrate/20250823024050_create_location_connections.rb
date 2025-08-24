class CreateLocationConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :location_connections do |t|
      t.references :location, null: false, foreign_key: true
      t.references :connected_location, null: false, foreign_key: { to_table: :locations }
      t.text :distance
      t.text :time_to_travel
      t.text :travel_method
      t.timestamps
    end

    add_index :location_connections, [ :location_id, :connected_location_id ], unique: true
  end
end
