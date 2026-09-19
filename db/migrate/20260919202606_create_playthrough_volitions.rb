# WHAT ONE PERSON DECIDED TO DO ON ONE TURN OF ONE GAME.
#
# `Playthrough::Blow`'s table one act over, and on the same side of the layer
# split: the WORLD says what somebody is after (`characters.desire_pursuit`,
# written by a seed file and by the generators and by no typed line) and a GAME
# says what they did about it. One row per present character per played line,
# `wait` included -- a turn somebody stood still is a choice they made, and the
# tally of these rows is what a later slice reads to ask whether a character
# has chosen the thing they say they want over the thing they need.
#
# `fact` IS THE ENGINE'S OWN SENTENCE and never model text. It is what
# `Playthrough::Moment` states to the narrator, in the slot the blows and the
# tolls already occupy, and it is written from the row that moved rather than
# from anything anybody said.
#
# `scene_id` IS NULLABLE FOR `playthrough_tolls`' REASON, and it means the same
# thing here: the Scene whose paragraph told the player about it. Nil is a row
# no paragraph has carried yet. A turn that writes no Scene at all -- an attack
# -- claims nothing, and the fact waits for the next paragraph.
class CreatePlaythroughVolitions < ActiveRecord::Migration[8.1]
  def change
    create_table :playthrough_volitions do |t|
      t.references :playthrough, null: false, foreign_key: true
      t.references :character, null: false, foreign_key: true
      # WHERE THEY WERE STANDING WHEN THEY DECIDED. The room the turn began in,
      # which is not always the room the player is in by the time the paragraph
      # is written -- you turned your back.
      t.references :location, null: false, foreign_key: true
      t.references :scene, null: true, foreign_key: true
      # THE TOKEN, VERBATIM: `wait`, `move:<location_id>`, `take:<item_id>`,
      # `give:<item_id>`, `follow`, `stop_following`. Opaque on purpose -- the
      # set it was drawn from is rebuilt from the records at apply time and a
      # token outside that set is rejected with a receipt.
      t.string :chosen, null: false
      # `applied`, `rejected` or `none` -- `Playthrough::NpcAction::Result`'s
      # three, because this is that class's twin and a receipt that read
      # differently would be a second vocabulary for one idea.
      t.string :status, null: false
      t.text :fact, null: false
      # WHICH OF THE FOUR OBJECTS OF DESIRE THE ACT SERVED, out of a fixed list
      # in code (`Playthrough::Volition::SERVES`). The engine's own answer,
      # derived from which weight table produced the token.
      t.string :serves, null: false
      t.integer :round, null: false
      t.timestamps
    end

    # WHAT THE NARRATOR READS: this game's rows that no paragraph has carried
    # yet, newest last. The same shape `index_playthrough_blows_on_playthrough_and_scene`
    # has, and for the same query.
    add_index :playthrough_volitions, [ :playthrough_id, :scene_id, :id ],
              name: "index_playthrough_volitions_on_playthrough_and_scene"
  end
end
