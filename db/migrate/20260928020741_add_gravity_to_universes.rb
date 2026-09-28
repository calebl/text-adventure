class AddGravityToUniverses < ActiveRecord::Migration[8.1]
  def change
    add_column :universes, :gravity, :string
  end
end
