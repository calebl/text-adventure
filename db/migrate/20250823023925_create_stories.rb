class CreateStories < ActiveRecord::Migration[8.0]
  def change
    create_table :stories do |t|
      t.string :title
      t.string :genre
      t.text :preface
      t.text :summary
      t.datetime :start_time
      t.references :universe, null: false, foreign_key: true

      t.timestamps
    end
  end
end
