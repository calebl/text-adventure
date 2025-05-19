class CreateStories < ActiveRecord::Migration[8.0]
  def change
    create_table :stories do |t|
      t.string :title
      t.string :description
      t.string :recap
      t.string :status
      t.string :user_id
      t.timestamps
    end

    create_table :messages do |t|
      t.string :role
      t.text :content
      t.integer :position
      t.references :story, foreign_key: true
      t.timestamps
    end

    create_table :characters do |t|
      t.string :name
      t.string :description
      t.references :story, foreign_key: true
      t.timestamps
    end

    create_table :locations do |t|
      t.string :name
      t.string :description
      t.references :story, foreign_key: true
      t.timestamps
    end

    create_table :items do |t|
      t.string :name
      t.string :description
      t.references :story, foreign_key: true
      t.timestamps
    end
  end
end
