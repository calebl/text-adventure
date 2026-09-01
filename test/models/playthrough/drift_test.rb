require "test_helper"

# The drift counter. What matters is that a row is written with enough evidence
# to judge it, that the count is a count, and above all that recording a
# measurement can never break the turn it was measuring.
class Playthrough::DriftTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @protagonist = create(:character, story: @story, is_protagonist: true)
    @here = create(:location, story: @story, name: "Ashgate Market")
    @playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
  end

  test "a drift is valid with a playthrough, an action and a command" do
    drift = build(:playthrough_drift, playthrough: @playthrough)

    assert_predicate drift, :valid?
  end

  test "an action outside the closed set is not a drift anything can produce" do
    drift = build(:playthrough_drift, playthrough: @playthrough, action: "examine")

    assert_not_predicate drift, :valid?
    assert_includes drift.errors[:action], "is not included in the list"
  end

  test "a drift needs the command that produced it, because the command is the evidence" do
    drift = build(:playthrough_drift, playthrough: @playthrough, command: "")

    assert_not_predicate drift, :valid?
  end

  test "record writes the row and joins what was offered into one readable line" do
    drift = Playthrough::Drift.record(
      playthrough: @playthrough, action: :move, command: "go through the cellar door",
      offered: [ "The Sunken Stair", "Ashgate Market" ], location: @here
    )

    assert_predicate drift, :persisted?
    assert_equal "move", drift.action
    assert_equal "The Sunken Stair, Ashgate Market", drift.offered
    assert_equal [ "The Sunken Stair", "Ashgate Market" ], drift.offered_names
  end

  # THE RULE THIS CLASS CANNOT BREAK. A measurement taken alongside a turn the
  # player is waiting on must not be able to fail that turn.
  test "record returns nil rather than raising when the row cannot be written" do
    assert_nothing_raised do
      assert_nil Playthrough::Drift.record(playthrough: nil, action: :move, command: "north", offered: [])
    end
  end

  test "record does not swallow the failure silently" do
    logged = []
    Rails.logger.stub(:warn, ->(message) { logged << message }) do
      Playthrough::Drift.record(playthrough: nil, action: :move, command: "north", offered: [])
    end

    assert_equal 1, logged.size
    assert_match(/could not be recorded/, logged.first)
  end

  test "an empty offered list reads as nothing having been on the table" do
    drift = Playthrough::Drift.record(playthrough: @playthrough, action: :talk, command: "talk to the ghost", offered: [])

    assert_predicate drift, :nothing_was_offered?
  end

  test "tally counts by action, which is the number the class exists to produce" do
    create(:playthrough_drift, playthrough: @playthrough)
    create(:playthrough_drift, playthrough: @playthrough)
    create(:playthrough_drift, :talk, playthrough: @playthrough)

    assert_equal({ "move" => 2, "talk" => 1 }, Playthrough::Drift.tally(@playthrough.drifts))
  end

  test "for_story gathers drift across every playthrough of one world" do
    other = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
    elsewhere = create(:playthrough)
    create(:playthrough_drift, playthrough: @playthrough)
    create(:playthrough_drift, playthrough: other)
    create(:playthrough_drift, playthrough: elsewhere)

    assert_equal 2, Playthrough::Drift.for_story(@story).count
  end

  test "drift goes when its playthrough goes" do
    create(:playthrough_drift, playthrough: @playthrough)

    assert_difference "Playthrough::Drift.count", -1 do
      @playthrough.destroy!
    end
  end

  # The scene is the narration under suspicion, and losing it must not lose the
  # measurement -- the drift is the durable half of the pair.
  test "a drift survives the scene it points at being destroyed" do
    scene = create(:scene, story: @story, location: @here)
    drift = create(:playthrough_drift, playthrough: @playthrough, scene: scene)

    scene.destroy!

    assert_predicate drift.reload, :persisted?
    assert_nil drift.scene_id
  end

  test "in_story_order reads in the order the story was played" do
    late = create(:playthrough_drift, playthrough: @playthrough, story_timestamp: 3.hours.from_now)
    early = create(:playthrough_drift, playthrough: @playthrough, story_timestamp: 1.hour.from_now)

    assert_equal [ early, late ], Playthrough::Drift.in_story_order.to_a
  end
end
