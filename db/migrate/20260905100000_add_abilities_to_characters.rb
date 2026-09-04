# THE THREE ABILITIES, AND THEY ARE THE WORLD'S. Three columns on `characters`,
# beside `level` and `hit_die` and on the same side of the line: who a person IS
# travels with the story, and what has HAPPENED to a body in one game is that
# game's (`playthrough_vitals`).
#
# The captain's ruling of 2026-09-04, evening: *"let's go with the 3 abilities"*
# -- strength, dexterity and will, and exactly those three. It corrects the
# earlier *"no abilities for now"*, which was a misunderstanding of the word.
#
# NULLABLE, DELIBERATELY, and this is `Character`'s own rule rather than a
# convenience: a character written before these columns existed has no
# abilities, and that is a real state `rake game:doctor` reports
# (`character_without_abilities`) rather than one this migration invents a value
# for. `rake game:backfill_stat_blocks` -- one of `bin/update`'s steps -- rolls
# 3d6 for every such row, offline and deterministically.
#
# THEY ARE NOT PART OF `Character#stat_block?` AND MUST NOT BECOME PART OF IT.
# That predicate gates `#max_hp`, which gates every `Playthrough::Vitals` row in
# the database; widening it would make every existing maximum nil and every
# existing game's condition unreadable between this migration and the backfill.
# `Character#abilities?` is the separate predicate, with its own validation and
# its own finding.
class AddAbilitiesToCharacters < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :strength, :integer
    add_column :characters, :dexterity, :integer
    add_column :characters, :will, :integer
  end
end
