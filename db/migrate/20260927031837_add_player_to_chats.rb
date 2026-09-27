class AddPlayerToChats < ActiveRecord::Migration[8.1]
  def change
    add_reference :chats, :player, null: true, foreign_key: true
  end
end
