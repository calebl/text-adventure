class AddEngineFactToScenes < ActiveRecord::Migration[8.1]
  def change
    add_column :scenes, :engine_fact, :text
  end
end
