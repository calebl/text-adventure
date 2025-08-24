class AddUserInputAndMakeOptionalReferencesToInteractions < ActiveRecord::Migration[8.0]
  def change
    add_column :interactions, :user_input, :text
    change_column_null :interactions, :scene_id, true
    change_column_null :interactions, :location_id, true
  end
end
