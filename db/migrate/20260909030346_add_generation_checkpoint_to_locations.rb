class AddGenerationCheckpointToLocations < ActiveRecord::Migration[8.1]
  def change
    add_column :locations, :generation_checkpoint, :json
  end
end
