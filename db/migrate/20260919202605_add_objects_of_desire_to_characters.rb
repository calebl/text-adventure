# WHAT A PERSON IS AFTER, AS SIX COLUMNS THE ENGINE CAN READ.
#
# `backstory` has always carried "their motivations and their goals" -- buried
# in a paragraph, in prose, unreadable by code. These six take the part the
# engine needs out of that paragraph and put it where a branch can reach it.
#
# FOUR PROSE FIELDS AND TWO LABELS, and the split is the whole point. The four
# are specific sentences about a specific person and nothing in the app ever
# parses, matches or branches on one; they are read by one prompt and stored.
# The two labels are the only thing the engine reads, and what a label DOES is
# a table in code (`Character::PURSUITS`, `Playthrough::Volition::Weights`) --
# this project's rule that a world supplies parameters and never behaviour,
# applied to a person.
#
# NULLABLE, EVERY ONE, and that is the same decision `characters.level` and the
# three abilities were given: a database older than the columns is a real state,
# `rake game:doctor` reports it and `rake game:backfill_desires` fills it in. A
# `presence: true` here would make every character written before today invalid
# and every seeded world unloadable between the migration and the backfill.
class AddObjectsOfDesireToCharacters < ActiveRecord::Migration[8.1]
  def change
    change_table :characters, bulk: true do |t|
      t.text :conscious_desire
      t.text :unconscious_desire
      t.text :recognized_need
      t.text :unrecognized_need
      # STRINGS RATHER THAN A DATABASE ENUM, which is what `characters.sex` and
      # `locations.danger` already are here: the closed list lives in Ruby
      # (`Character::PURSUITS`) so that adding a label is a code change with
      # tests around it rather than a migration.
      t.string :desire_pursuit
      t.string :need_pursuit
    end
  end
end
