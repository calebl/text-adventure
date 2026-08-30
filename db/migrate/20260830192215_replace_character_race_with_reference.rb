class ReplaceCharacterRaceWithReference < ActiveRecord::Migration[8.0]
  def up
    # Characters pick a race from their universe's generated list rather than
    # inventing one, so the free-text column becomes a foreign key.
    #
    # Existing characters hold a free-text race with no corresponding Race
    # record, and there is no sound way to map one onto the other. They are
    # generated content, so discard them rather than invent a backfill.
    say_with_time "discarding characters with no assignable race" do
      Character.delete_all
    end

    remove_column :characters, :race
    add_reference :characters, :race, null: false, foreign_key: true
  end

  def down
    remove_reference :characters, :race, foreign_key: true
    add_column :characters, :race, :string
  end
end
