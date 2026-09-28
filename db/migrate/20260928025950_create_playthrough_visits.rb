# EVERY ROOM ONE GAME HAS STOOD IN, one row per (playthrough, location).
#
# The scene chain used to be the only record of where a game had been, and a
# move with no model writes no `Scene` (`Playthrough::Mechanics#stand_in`), so
# an offline walk stood in rooms nothing recorded. `Story::Doctor` then read
# every condition row written at first contact there as a row for somebody
# the game never met. See `Playthrough::Visit`.
#
# No backfill: a game that walked offline before this table existed left no
# record to backfill from, and the doctor still reads the scene chain beside
# this table, so every narrated move is covered either way.
class CreatePlaythroughVisits < ActiveRecord::Migration[8.1]
  def change
    create_table :playthrough_visits do |t|
      t.references :playthrough, null: false, foreign_key: true
      t.references :location, null: false, foreign_key: true
      t.timestamps
    end

    # ONE ROW PER ROOM PER GAME, so taking a visit twice is the second one
    # doing nothing.
    add_index :playthrough_visits, %i[playthrough_id location_id], unique: true,
              name: "index_playthrough_visits_on_playthrough_and_location"
  end
end
