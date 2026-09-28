require "test_helper"

# A RUN DATABASE FROM BEFORE THE SCHEMA THE SCORER READS.
#
# `rake eval:score` re-reads run sets swept long ago, each against its own
# SQLite file, with today's code. A set from before the item layers has no
# `items.playthrough_id` or `items.disposition`, none of the world-event
# scheduling columns, and no `playthrough_overreaches` table -- and scoring one
# used to raise on the first of those it met, so no old baseline could be
# scored at all. This builds such a database from today's schema with those
# pieces taken out, which is the shape the stored sets really have, and scores
# it: the two checks that need what is missing report unavailable, and the
# rest still answer.
class Eval::OldRunSetTest < ActiveSupport::TestCase
  # The run database is a second SQLite file the connection is swapped onto,
  # which a transaction on the test database cannot wrap.
  self.use_transactional_tests = false

  TITLE = "A World Swept Before The Item Layers".freeze

  setup do
    @dir = Rails.root.join("tmp/old-run-set-test-#{SecureRandom.hex(4)}")
    @dir.mkpath
    @original = ActiveRecord::Base.connection_db_config
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: @dir.join("run.sqlite3").to_s)
    ActiveRecord::Schema.verbose = false
    load Rails.root.join("db/schema.rb")
    reset_columns

    story = create(:story, title: TITLE)
    hall = create(:location, story: story, name: "The Long Hall")
    create(:character, story: story, fullname: "Ada Oldset", is_protagonist: true, location: hall)
    opening = create(:scene, :opening, story: story, location: hall, description: "You stand in the hall.")
    create(:scene, story: story, location: hall, previous_scene: opening, typed: "look",
                   story_timestamp: opening.story_timestamp + 1.minute,
                   description: "The hall runs on, and a lamp burns at its far end.")

    connection = ActiveRecord::Base.connection
    connection.drop_table :playthrough_overreaches
    connection.remove_column :items, :playthrough_id
    connection.remove_column :items, :disposition
    %i[playthrough_id scheduled_for fired_at].each { |column| connection.remove_column :world_events, column }
    reset_columns
  end

  teardown do
    ActiveRecord::Base.establish_connection(@original)
    reset_columns
    FileUtils.rm_rf(@dir)
  end

  test "an old run database scores, with the checks it cannot answer reported unavailable" do
    run = Eval::RunSet.read({ "story" => TITLE, "rep" => 1, "turns" => [] }, io: nil)
    readings = run.readings.index_by(&:code)

    assert_not readings.fetch(:item_not_held).available
    assert_not readings.fetch(:named_more_than_one).available
    assert readings.fetch(:truncated_prose).available, "a check that reads nothing missing still answers"
    assert readings.fetch(:still_run).available, "world events read the whole table when nothing tells the world's apart"
    assert_equal 1, run.scenes
  end

  test "the schema probe asks the connected database, not the model" do
    assert_not Story::Audit.schema_has?(:items, :playthrough_id)
    assert_not Story::Audit.schema_has?(:playthrough_overreaches)
    assert Story::Audit.schema_has?(:items, :name)
  end

  private

  def reset_columns
    [ Item, WorldEvent, Playthrough::Overreach ].each(&:reset_column_information)
  end
end
