# A FIGHT RESOLVES, AND WHAT IT LEAVES BEHIND IS TWO THINGS ON THIS GAME'S SIDE
# OF THE LAYER SPLIT -- neither of them a column on a `Character`.
#
#   playthrough_blows           ONE ROW PER BLOW, and it is the durable
#                               per-round record. A round is a turn (the
#                               captain's call C5), and a turn of a fight writes
#                               no `Scene` -- `Story#clock` is
#                               `MAX(scenes.story_timestamp)` and `Scene`
#                               requires a description, so a Scene per round
#                               would put a paragraph of engine copy in the
#                               column `Story::Audit` and `Eval::Richness` read
#                               as NARRATION, once per exchange. This table
#                               holds the exchange instead and ONE Scene closes
#                               the fight (`Playthrough::Fight`), so the audit's
#                               exposure is one row per fight rather than one
#                               per round.
#   playthrough_vitals.         WHO THIS GAME HAS PICKED A FIGHT WITH. The
#   provoked_at                 captain's sixth ruling of 2026-09-05: *"anyone
#                               can be attacked"*, and being attacked makes
#                               somebody a foe FOR THIS PLAYTHROUGH ONLY. It is
#                               a moment on the STORY's clock rather than a
#                               boolean, for `playthroughs.ended_at`'s reason --
#                               when it happened is worth as much as that it
#                               did -- and it is on the per-playthrough row
#                               rather than on `characters.hostile` because the
#                               world's hostility is the world's: playthrough A
#                               swinging at the landlord must not make him an
#                               enemy in playthrough B.
#
# EVERY COLUMN ON `playthrough_blows` IS A FACT THE ENGINE DECIDED, and none of
# them came from a model. `damage` is one die of the attacker's `hit_die`
# (`Playthrough::Turn#damage_for`), `sequence` is which roll of this game it was
# -- the seed `Roll.generator` was handed, read off the row count rather than
# off a counter in memory, so a replay a year later throws the same dice --
# and `round` is which turn of the fight it landed on.
#
# `scene_id` IS NULLABLE AND NIL IS THE WHOLE OF "THIS FIGHT IS STILL ON":
# `Playthrough::Fight#open_blows` is the rows with no closing Scene, and closing
# a fight is the one statement that stamps them.
class RecordTheBlowsOfAFight < ActiveRecord::Migration[8.1]
  def change
    create_table :playthrough_blows do |t|
      t.references :playthrough, null: false, foreign_key: true
      t.references :attacker, null: false, foreign_key: { to_table: :characters }
      t.references :target, null: false, foreign_key: { to_table: :characters }
      # WHERE IT HAPPENED, because a fight is a fight in a ROOM: it ends when
      # the party is no longer standing in it, and nothing else on the row can
      # answer that -- the party carries no whereabouts, so the attacker's
      # `location_id` is nil for every blow the player throws.
      t.references :location, null: false, foreign_key: true
      t.integer :damage, null: false
      t.integer :hp_after, null: false
      t.integer :round, null: false
      t.integer :sequence, null: false
      t.datetime :story_timestamp, null: false
      # The one Scene that closes the fight this blow belongs to. Nullified
      # rather than destroyed with it: the blow is the measurement and the
      # scene is only the sentence about it.
      t.references :scene, null: true, foreign_key: true
      t.timestamps
    end

    # THE ONE QUERY THIS TABLE IS READ WITH: this game's open blows, oldest
    # first. `Playthrough::Fight` asks it at the end of every turn.
    add_index :playthrough_blows, %i[playthrough_id scene_id id],
              name: "index_playthrough_blows_on_playthrough_and_scene"

    add_column :playthrough_vitals, :provoked_at, :datetime
  end
end
