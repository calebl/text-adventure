class OwnTakingAndCountDrift < ActiveRecord::Migration[8.1]
  def change
    # AN ITEM IS EITHER IN SOMEBODY'S HANDS OR LYING IN A PLACE. It was only
    # ever the first, which left the game with nothing to pick up: `take` had
    # no closed set to resolve against, so taking could only ever be a sentence
    # the narrator wrote. `Item#location` is what makes it a state change the
    # app can own -- see Playthrough::Turn#take_item.
    change_column_null :items, :character_id, true
    add_reference :items, :location, null: true, foreign_key: true
    add_index :items, [ :location_id, :character_id ]

    # WHAT THE PLAYER REACHED FOR THAT THE RECORDS DO NOT HAVE.
    #
    # One row per turn on which the classifier resolved a move, a talk or a
    # take against a closed set and found nothing in it -- which is how an exit
    # the narration invented becomes observable without asking a model
    # anything. Deliberately NOT pruned with the conversations: this is the
    # measurement, and a measurement that expires cannot be watched over time.
    create_table :playthrough_drifts do |t|
      t.references :playthrough, null: false, foreign_key: true
      # The narration the player had just read, which is where an invented exit
      # would have come from. Nullified rather than cascaded: the drift is the
      # durable half.
      t.references :scene, null: true, foreign_key: true
      t.references :location, null: true, foreign_key: true
      t.string :action, null: false
      t.text :command, null: false
      # The closed set that WAS on the table, so a reader can judge the flag
      # without reconstructing the room as it stood.
      t.text :offered
      t.datetime :story_timestamp

      t.timestamps
    end

    add_index :playthrough_drifts, [ :playthrough_id, :story_timestamp ]
    add_index :playthrough_drifts, :action
  end
end
