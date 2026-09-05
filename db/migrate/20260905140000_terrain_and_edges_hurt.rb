# A PLACE CAN COST YOU HIT POINTS, AND SO CAN THE WAY YOU GOT THERE.
#
# The captain's request, second half: *"certain terrain or actions should also
# cause damage."* Four columns and one table, and every one of them is on the
# side of the layer split its subject is already on -- the hazard is the
# WORLD's (a seed file writes it, no model and no typed line ever does), and
# what it cost this game is the PLAYTHROUGH's.
#
#   locations.hazard          WHAT A PLACE DOES TO SOMEBODY STANDING IN IT: a
#   locations.hazard_die      key into `Location::HAZARDS` and the die that is
#                             thrown when the save is missed. A key rather than
#                             a rule, which is `locations.danger`'s own shape
#                             one column over and `WorldMechanic`'s doctrine
#                             stated for a room: a world supplies parameters and
#                             never behaviour.
#   location_connections.     THE SAME THING ON A DOORWAY, and this is the first
#   hazard / hazard_die       mechanic that WANTS the directed edge. Connections
#                             are two rows per door (the ruling of 2026-09-03),
#                             so a hazard on one of them is one-way BY
#                             CONSTRUCTION and nothing has to enforce it: the
#                             drop into the hulk hurts and the climb back out
#                             does not. A ONE-WAY HAZARD IS NOT A ONE-WAY EXIT
#                             -- the door stays two-way, both rows still lead
#                             both ways, and only the cost differs. One-way
#                             exits stay unsupported and deliberately deferred.
#   playthrough_tolls         WHAT ONE HAZARD TOOK OFF ONE BODY IN ONE GAME.
#
# ALL FOUR ARE NULLABLE AND THERE IS NO BACKFILL, which is a different answer
# from the one `locations.danger` gave and it is the right one for a different
# question. A danger is a SHARE of a die -- every room has one, and `safe` is
# the honest zero every existing row already is. A hazard is a THING A PLACE
# DOES, and almost no room does anything: NULL says "this room does nothing to
# you", which is true of every row ever written, and a default key would be
# inventing a table entry for rows nobody authored. So `bin/update` gains no
# step -- there is nothing about an existing database that is wrong.
#
# WHY A TOLL IS NOT A BLOW, and it is two reasons rather than a preference.
# `playthrough_blows.attacker_id` is NOT NULL and a hazard has no attacker: the
# tide has no hit die and cannot be swung back at. And `Playthrough::Fight`
# reads `Playthrough::Blow.open` as *the fight that is still on* -- a hazard row
# in that table would open a fight with nobody in it, which `Fight#over?` would
# close on the same turn with a `Scene` saying a fight nobody was in had ended.
# The fight-end rule must not treat a hazard as a foe, so the hazard keeps its
# own record and `Playthrough::Turn#harm!` stays the one writer of a hit point.
class TerrainAndEdgesHurt < ActiveRecord::Migration[8.1]
  def change
    add_column :locations, :hazard, :string
    add_column :locations, :hazard_die, :integer
    add_column :location_connections, :hazard, :string
    add_column :location_connections, :hazard_die, :integer

    create_table :playthrough_tolls do |t|
      t.references :playthrough, null: false, foreign_key: true
      # WHOSE BODY PAID IT. A column rather than "the protagonist" because
      # `Playthrough::Turn#harm!` takes a character and there is no reason a
      # companion standing in the same water would not pay the same toll; what
      # is not built is anybody but the party being in it (`#targets`).
      t.references :character, null: false, foreign_key: { to_table: :characters }
      # WHERE THE BODY WAS STANDING WHEN IT WAS PAID -- the room for a room's
      # hazard, and the room ARRIVED IN for a doorway's, because that is where
      # the body is by the time the walk is over.
      t.references :location, null: false, foreign_key: true
      # AND THE DOORWAY, WHEN IT WAS A DOORWAY'S. Nil for a room's own hazard,
      # and it is the whole of what tells the two apart -- the one directed row
      # that was walked, so the record says which way it was walked as well as
      # that it was.
      t.references :location_connection, null: true, foreign_key: true
      # WHICH ENTRY OF WHICH TABLE, kept on the row rather than re-read off the
      # location: a re-seed may change what a room does, and what it did to you
      # last Tuesday is not a thing the file gets to edit afterwards.
      t.string :hazard, null: false
      # WHETHER THE BODY GOT CLEAR OF IT -- `d20 <= the named ability` through
      # `Character#check`, the one kernel. True with no roll at all for a hazard
      # whose entry has `save: nil`, which is a real thing and is why this is a
      # column rather than `damage.zero?`.
      t.boolean :saved, null: false, default: false
      t.integer :damage, null: false
      t.integer :hp_after, null: false
      t.integer :sequence, null: false
      t.datetime :story_timestamp, null: false
      # THE SCENE THAT TOLD THE PLAYER ABOUT IT, and NIL IS THE WHOLE OF "the
      # prose has not said this yet" -- `Playthrough::Blow`'s `scene_id` read
      # for the other thing that hurts. `Playthrough::Moment` states the untold
      # ones as facts and `Playthrough::Turn#play` claims them with the turn's
      # own Scene, so one toll is narrated once.
      t.references :scene, null: true, foreign_key: true
      t.timestamps
    end

    # THE ONE QUERY THIS TABLE IS READ WITH: this game's untold tolls, oldest
    # first. `Playthrough::Moment` asks it once per narrated turn.
    add_index :playthrough_tolls, %i[playthrough_id scene_id id],
              name: "index_playthrough_tolls_on_playthrough_and_scene"
  end
end
