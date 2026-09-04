# THE CONDITION OF ONE BODY IN ONE GAME, and the death that ends a playthrough.
#
# The captain's ruling of 2026-09-04 applied to people: the world owns the
# template (`characters.level`, `characters.hit_die`) and the playthrough owns
# the instance. One row per (playthrough, character), written lazily at first
# contact exactly where `Item::Snapshot` copies a room's things -- so an ABSENT
# row means unhurt, which is what almost every NPC in a world will always be.
#
# `playthroughs.ended_at` is the other half: *"zero hit points means death.
# Playthrough is over and you can't do anything else."* The marker is on the
# playthrough because the playthrough is what stops, and it is a moment on the
# STORY's clock rather than the wall clock (AGENTS.md -> *Story time*).
class CreatePlaythroughVitals < ActiveRecord::Migration[8.1]
  def change
    create_table :playthrough_vitals do |t|
      t.references :playthrough, null: false, foreign_key: true
      t.references :character, null: false, foreign_key: true
      t.integer :hp_current, null: false
      t.timestamps
    end

    # ONE ROW PER BODY PER GAME. The uniqueness is the whole of what makes
    # `Playthrough#vitals_for` a single answer, so it is an index and not only
    # a validation.
    add_index :playthrough_vitals, %i[playthrough_id character_id], unique: true,
              name: "index_playthrough_vitals_on_playthrough_and_character"

    add_column :playthroughs, :ended_at, :datetime
  end
end
