class AddPlayerToPlaythroughs < ActiveRecord::Migration[8.1]
  def change
    add_reference :playthroughs, :player, null: true, foreign_key: true
  end
end
