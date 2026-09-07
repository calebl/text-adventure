class AStoryGetsAnArc < ActiveRecord::Migration[8.1]
  def change
    # THE WORLD'S OWN ARC. A quest belongs to the STORY and never to a
    # playthrough: two people playing one world are walking the same arc, and
    # which beats each of them has reached is the per-playthrough half below.
    create_table :quests do |t|
      t.references :story, null: false, foreign_key: true
      # NIL IS THE MAIN ARC. A child quest is a side quest, which is the whole
      # of the distinction `contributes` then qualifies.
      t.references :parent_quest, foreign_key: { to_table: :quests }
      t.string :title, null: false
      t.text :premise, null: false
      t.string :status, null: false, default: "open"
      t.boolean :contributes, null: false, default: true
      # WHICH PATH WROTE IT: a seed file, or the generator at `rake game:new`.
      t.string :origin, null: false, default: "seeded"

      t.timestamps
    end
    add_index :quests, [ :story_id, :title ], unique: true

    # THE BEATS THE ARC IS MADE OF. `target_name` is the name the arc is
    # WAITING for and `target` is the row it eventually resolves to -- see
    # `Quest::Step` for why a step has two states and the schema has to say
    # which.
    create_table :quest_steps do |t|
      t.references :quest, null: false, foreign_key: true
      t.integer :position, null: false
      t.text :summary, null: false
      t.string :trigger_kind, null: false
      t.string :target_name
      t.text :teaser
      t.references :target, polymorphic: true
      t.integer :minutes
      t.datetime :bound_at

      t.timestamps
    end
    add_index :quest_steps, [ :quest_id, :position ], unique: true

    # THE ENDINGS. Several per quest, one marked as the default the world was
    # born with -- the captain's note of 2026-09-06, *"multiple endings to a
    # quest must be possible"*.
    create_table :quest_outcomes do |t|
      t.references :quest, null: false, foreign_key: true
      t.string :name, null: false
      t.text :summary, null: false
      t.boolean :is_default, null: false, default: false

      t.timestamps
    end
    add_index :quest_outcomes, [ :quest_id, :name ], unique: true

    # WHICH BEATS ONE GAME HAS REACHED. The `Item` layer split applied to
    # beats: two players of one world reach them in their own order and at
    # their own moment on the story clock.
    create_table :playthrough_beats do |t|
      t.references :playthrough, null: false, foreign_key: true
      t.references :quest_step, null: false, foreign_key: true
      t.datetime :reached_at, null: false

      t.timestamps
    end
    add_index :playthrough_beats, [ :playthrough_id, :quest_step_id ], unique: true

    # AND WHICH ENDING ONE GAME REACHED, on the same terms and for the same
    # reason.
    create_table :playthrough_endings do |t|
      t.references :playthrough, null: false, foreign_key: true
      t.references :quest_outcome, null: false, foreign_key: true
      t.datetime :reached_at, null: false

      t.timestamps
    end
    add_index :playthrough_endings, [ :playthrough_id, :quest_outcome_id ], unique: true

    # ONE EVENT STREAM, WHICH IS THE CAPTAIN'S CALL 8 OF 2026-09-06: *"one
    # event stream could work"*. A failed quest is not a mechanic, so the
    # column that used to be the only way into this table goes nullable and
    # `source` says which writer wrote the row.
    #
    # THE BACKFILL IS THE WHOLE OF WHAT MAKES IT SAFE: every row that exists
    # today came from a mechanic, so every row is stamped with that source
    # before the column is made NOT NULL.
    change_column_null :world_events, :world_mechanic_id, true
    add_column :world_events, :source, :string
    add_column :world_events, :playthrough_id, :integer
    add_index :world_events, :playthrough_id

    reversible do |direction|
      direction.up do
        execute "UPDATE world_events SET source = 'world_mechanic' WHERE source IS NULL"
      end
    end

    change_column_null :world_events, :source, false
  end
end
