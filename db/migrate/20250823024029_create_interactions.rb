class CreateInteractions < ActiveRecord::Migration[8.0]
  def change
    create_table :interactions do |t|
      t.references :character, null: false, foreign_key: true
      t.references :scene, null: false, foreign_key: true
      t.references :location, null: false, foreign_key: true
      t.text :pre_thought
      t.text :pre_feeling
      t.text :action
      t.text :post_feeling
      t.text :post_thought
      t.text :inner_resolution
      t.text :summary

      t.timestamps
    end
  end
end
