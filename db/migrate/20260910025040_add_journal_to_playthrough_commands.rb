class AddJournalToPlaythroughCommands < ActiveRecord::Migration[8.1]
  def change
    add_column :playthrough_commands, :journal, :json, default: {}, null: false
  end
end
