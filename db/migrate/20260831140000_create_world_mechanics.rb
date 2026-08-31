# The world-mechanics engine: a fixed catalogue of Ruby operations over records,
# run on a STORY-TIME schedule.
#
# Three tables and one boolean, and the split between them is the design:
#
#   locations.mobile     which places move. A parameter of the world.
#   world_mechanics      which operation runs how often, and its in-fiction
#                        reason. `kind` and `cadence` are keys into fixed tables
#                        in code -- the LocationConnection::DISTANCES precedent.
#                        A generated or hand-seeded world supplies parameters,
#                        never behaviour.
#   world_events         what actually happened, in story time. The audit trail
#                        that makes the mechanic checkable from a cold process.
#
# `last_run_at` and `occurred_at` are STORY time, not wall clock. That is what
# makes the mechanic survive a restart: catching up is arithmetic on two
# datetimes read out of the database, so a process that was down for a week
# resumes exactly where the story left off and never re-runs a night it ran.
class CreateWorldMechanics < ActiveRecord::Migration[8.1]
  def change
    add_column :locations, :mobile, :boolean, default: false, null: false

    # `Story#clock` is a MAX over this column, read on every turn.
    add_index :scenes, [ :story_id, :story_timestamp ]

    create_table :world_mechanics do |t|
      t.references :story, null: false, foreign_key: true
      # The natural key WorldSeed::Loader matches on, so a hand-edited seed file
      # can carry more than one mechanic and re-seeding updates rather than
      # duplicates.
      t.string :name, null: false
      t.string :kind, null: false
      t.string :cadence, null: false
      t.text :description
      t.datetime :last_run_at

      t.timestamps
    end

    add_index :world_mechanics, [ :story_id, :name ], unique: true

    create_table :world_events do |t|
      t.references :world_mechanic, null: false, foreign_key: true
      t.references :story, null: false, foreign_key: true
      t.datetime :occurred_at, null: false
      t.text :summary, null: false

      t.timestamps
    end

    add_index :world_events, [ :story_id, :occurred_at ]

    # Which places an event moved. Rails' habtm default name for
    # Location <-> WorldEvent, alphabetically.
    create_table :locations_world_events, id: false do |t|
      t.references :location, null: false, foreign_key: true
      t.references :world_event, null: false, foreign_key: true
    end

    add_index :locations_world_events, [ :world_event_id, :location_id ], unique: true
  end
end
