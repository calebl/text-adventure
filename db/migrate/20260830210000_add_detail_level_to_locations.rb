# A location exists in one of two states: a *stub* -- a name and a one-line
# teaser, created so the exits out of a room are real records the moment the
# narrator mentions them -- and a *realized* location, with the full
# description and lore the player reads on arrival.
#
# `detail_level` rather than a `generated_at` timestamp: the column answers
# "what is this record" rather than "when did something happen to it", it reads
# the same in a query as it does in the narrative, and it leaves room for a
# third level later (a summarized location, say) without overloading nil.
# `created_at` already records when the stub appeared.
class AddDetailLevelToLocations < ActiveRecord::Migration[8.1]
  def up
    add_column :locations, :detail_level, :string, null: false, default: "stub"
    add_column :locations, :teaser, :text
    add_index :locations, [ :story_id, :detail_level ]

    # Every location generated before this migration was written with a
    # description and lore, which is exactly what "realized" means.
    execute <<~SQL.squish
      UPDATE locations SET detail_level = 'realized'
      WHERE description IS NOT NULL AND TRIM(description) != ''
    SQL
  end

  def down
    remove_index :locations, [ :story_id, :detail_level ]
    remove_column :locations, :teaser
    remove_column :locations, :detail_level
  end
end
