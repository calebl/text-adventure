# THE STAT BLOCK, AND IT IS THE WORLD'S. Two columns on `characters`, on the
# same side of the line `characters.location_id` and the world's own `Item` rows
# sit on: who a person IS travels with the story, and what has HAPPENED to a
# body in one game is that game's (`playthrough_vitals`).
#
# NULLABLE, DELIBERATELY, and this is `Character`'s own rule rather than a
# convenience: a character written before these columns existed has no stat
# block, and that is a real state `rake game:doctor` reports
# (`character_without_a_stat_block`) rather than one this migration invents a
# value for. `rake game:backfill_stat_blocks` -- one of `bin/update`'s steps --
# rolls one for every such row, offline and deterministically.
class AddStatBlockToCharacters < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :level, :integer
    add_column :characters, :hit_die, :integer
  end
end
