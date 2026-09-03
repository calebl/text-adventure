class RecordWhatTheTurnDid < ActiveRecord::Migration[8.1]
  # WHAT THE TURN DID, as two columns on the turn that did it.
  #
  # `scenes.typed` is the raw line the player typed and `scenes.location_id` is
  # where they ended up: the records carry what the world IS after a turn and
  # never what the turn DID. So every check in `Story::Audit` reads one state,
  # `unrecorded_departure` and `unrecorded_arrival` infer movement by comparing
  # two location ids, and the largest measured defect in the game -- prose on a
  # resolved `take` denying the pickup on 28 of 32 take turns of the 480-turn
  # baseline -- is invisible to all nine of them.
  #
  # `resolved_action` is what `Playthrough::Classifier` resolved the line to,
  # out of `Playthrough::IntentSchema::INTENTS`. `acted_on` is the record it
  # resolved to: the Location moved to, the Character spoken to, the Item taken
  # or dropped. Polymorphic because the closed set the classifier answers from
  # is already three kinds of record and collapsing them into three nullable
  # foreign keys would make "which one is set" a thing every reader works out.
  #
  # BOTH NULLABLE, and they stay nullable. Every turn written before this
  # migration has neither, an opening arrival has neither by right, and a turn
  # whose reach resolved to nothing has an action and no record -- which is a
  # fact about that turn and not a gap. `rake game:backfill_transitions` labels
  # what the stored classifier conversations can still answer for.
  def change
    add_column :scenes, :resolved_action, :string
    add_reference :scenes, :acted_on, polymorphic: true, null: true

    add_index :scenes, [ :story_id, :resolved_action ]
  end
end
