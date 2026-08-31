# Two characters in one story cannot share a full name. The validation on
# Character reports it in the right place; this index is what makes it true
# under concurrency, and it is written on LOWER(fullname) so the database
# enforces exactly what the case-insensitive validation checks rather than
# something slightly weaker.
class AddUniqueFullnamePerStoryToCharacters < ActiveRecord::Migration[8.1]
  def change
    add_index :characters, "story_id, LOWER(fullname)",
              unique: true,
              name: "index_characters_on_story_id_and_lower_fullname"
  end
end
