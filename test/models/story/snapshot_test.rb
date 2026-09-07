require "test_helper"

# The column, and the two things it has to be true of: it survives a re-seed,
# and it goes when the story goes. Both are properties of it being a column
# rather than a file, and both are asserted rather than reasoned about --
# `Story::Snapshot`'s header is the argument, this is the proof.
class Story::SnapshotTest < ActiveSupport::TestCase
  include ForkableWorld

  test "captures the story as WorldSeed::Exporter sees it" do
    story = seeded_world

    document = Story::Snapshot.capture!(story)

    assert_equal WorldSeed::FORMAT, document["format"]
    assert_equal "A Forkable World", document.dig("story", "title")
    assert_equal [ "The Office", "The Hallway" ], document["locations"].map { |row| row["name"] }
    assert_equal document, Story::Snapshot.for(story.reload)
  end

  test "captures with no model call" do
    story = seeded_world

    BaseAgent.stub(:new, ->(*) { flunk "snapshotting a world asked a model something" }) do
      Story::Snapshot.capture!(story)
    end

    assert Story::Snapshot.for(story.reload).present?
  end

  test "a story with no snapshot reads as none rather than raising" do
    assert_nil Story::Snapshot.for(create(:story))
  end

  # A caller reading the column to find out whether there IS one must not be the
  # thing that raises on a broken one -- `WorldSeed.checked_in_document`'s rule.
  test "a malformed snapshot reads as none" do
    story = seeded_world
    story.update_column(:generation_snapshot, "{{{ not yaml")

    assert_nil Story::Snapshot.for(story)
  end

  # A snapshot with no opening arrival is one `WorldSeed::Loader` will not load,
  # so it is refused when it is taken rather than when it is used.
  test "refuses to store a world with no opening arrival" do
    story = seeded_world
    story.opening_scene.destroy!

    error = assert_raises(Story::Snapshot::NotSnapshottable) { Story::Snapshot.capture!(story.reload) }
    assert_match "opening arrival", error.message
    assert_nil story.reload.generation_snapshot
  end

  test "re-asserting the world files over the database leaves a snapshot alone" do
    story = seeded_world
    Story::Snapshot.capture!(story)
    stored = story.reload.generation_snapshot

    # A re-seed is the loader running again over the story it already wrote,
    # which is what `rake game:reseed` does to every checked-in world.
    WorldSeed::Loader.new(world_document).load!

    assert_equal stored, story.reload.generation_snapshot
  end

  test "the snapshot goes when the story goes" do
    story = seeded_world
    Story::Snapshot.capture!(story)

    Story::Deletion.new(story).destroy!(confirm: story.title)

    assert_equal 0, Story.where(id: story.id).count
  end
end
