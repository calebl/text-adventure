class CountALineThatNamedTwoThings < ActiveRecord::Migration[8.1]
  def change
    # WHAT THE PLAYER ASKED FOR THAT THE TURN DID NOT DO.
    #
    # One row per turn on which the typed line named more than one thing the
    # records really have -- "take the index and the apron" -- and the loop did
    # one of them, because one line is one act. Both halves resolved, so
    # `playthrough_drifts` never saw it: drift is a reach that found NOTHING,
    # and this is a reach that found more than a turn can answer. The two are
    # different facts about the world and are counted apart.
    #
    # Deliberately NOT pruned with the conversations, for the same reason
    # drift is not: this is the measurement.
    create_table :playthrough_overreaches do |t|
      t.references :playthrough, null: false, foreign_key: true
      # The narration the player had just read when they typed it. Nullified
      # rather than cascaded: the measurement is the durable half.
      t.references :scene, null: true, foreign_key: true
      t.references :location, null: true, foreign_key: true
      t.string :action, null: false
      t.text :command, null: false
      # The two names, so a reader can judge the row without reconstructing the
      # room: what the turn acted on, and the one it did not.
      t.text :acted, null: false
      t.text :unacted, null: false
      t.datetime :story_timestamp

      t.timestamps
    end

    add_index :playthrough_overreaches, [ :playthrough_id, :story_timestamp ]
    add_index :playthrough_overreaches, :action
  end
end
