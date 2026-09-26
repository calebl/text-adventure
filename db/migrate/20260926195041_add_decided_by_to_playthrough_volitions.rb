class AddDecidedByToPlaythroughVolitions < ActiveRecord::Migration[8.1]
  def change
    add_column :playthrough_volitions, :decided_by, :string
    add_column :playthrough_volitions, :system_one_error, :string
  end
end
