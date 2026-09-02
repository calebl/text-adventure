class AttachAVerdictToATurn < ActiveRecord::Migration[8.1]
  def change
    # THE CAPTAIN'S JUDGEMENT OF ONE TURN, recorded while he is playing it.
    #
    # An evaluation instrument, not a social feature: which model narrates the
    # world and which writes conversation are open questions, and a verdict
    # attached to a real turn during real play is better evidence than a blind
    # read of a generated passage. So the row has to be readable six weeks
    # later, by which time the receipts for that turn are gone.
    #
    # WHICH IS WHY THE PROVENANCE IS FROZEN HERE RATHER THAN REFERENCED.
    # `Chat#answering_model_ids` knows which model answered -- including after
    # a rotation past one that failed -- but `Playthrough#prune_conversations!`
    # destroys the one-shot conversations older than `Chat::KEEP_TURNS` on every
    # turn, so a reference would resolve to nothing on any turn worth comparing
    # against. The five columns below the divider are copies taken at the moment
    # the verdict is recorded and never touched again; everything above it is a
    # reference to a record that outlives the pruner.
    create_table :playthrough_feedbacks do |t|
      t.references :playthrough, null: false, foreign_key: true
      # The turn being judged. `Scene` is durable -- its `description`, its
      # `typed` and its `story_timestamp` are all still there long after the
      # conversations are pruned -- so this stays a reference and the prose is
      # read through it rather than copied.
      t.references :scene, null: false, foreign_key: true

      t.string :verdict, null: false
      # Optional, and deliberately so: a verdict that is only worth recording
      # with an essay attached will not be recorded at all mid-play.
      t.text :note

      # --- frozen at record time; see Playthrough::Feedback.provenance_for ---

      # THE ANSWER TO THE QUESTION THIS TABLE EXISTS FOR: which model wrote the
      # prose that is being judged, and which of the app's agents it was writing
      # as. Nil when the receipts had already been pruned before the verdict was
      # recorded -- which is a real state and is reported as one rather than
      # guessed at.
      #
      # A single value and indexed, because it is the key every later comparison
      # groups by. Which is also why it is stored rather than derived from the
      # list below it: a comma-joined column is a poor thing to GROUP BY.
      t.string :prose_model
      t.string :prose_purpose
      # EVERY MODEL THAT ATTEMPTED THE PROSE on that turn, in call order.
      # `prose_model` is the last of these -- the one whose words were kept --
      # and more than one entry means `BaseAgent` rotated on the call being
      # judged, past a model that failed or a refusal it would not write. That
      # is a different fact from the one below and cannot be read off it: a
      # rotation in the classifier says nothing about the prose.
      t.text :prose_models
      # Every model that answered ANYTHING on that turn, in call order. A talk
      # turn is two passes and an arrival is three calls, so the prose model
      # alone does not say who classified or who wrote the character's side.
      t.text :answering_models
      # The other half of the receipt, and it goes with the same pruner.
      t.integer :input_tokens
      t.integer :output_tokens

      t.timestamps
    end

    # ONE VERDICT PER TURN PER PLAYTHROUGH, which is what makes recording and
    # amending the same request. Scoped by playthrough rather than by scene
    # alone because a story's opening arrival is world data shared by every
    # playthrough of it -- two players judging the same opening are two
    # judgements.
    add_index :playthrough_feedbacks, [ :playthrough_id, :scene_id ], unique: true
    add_index :playthrough_feedbacks, :verdict
    add_index :playthrough_feedbacks, :prose_model
  end
end
