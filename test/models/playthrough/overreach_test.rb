require "test_helper"

# The row that makes "one line is one act" a number instead of an impression.
#
# What matters here is the same thing that matters about `Playthrough::Drift`:
# it is written without being able to break the turn it measures, and it is
# never confused with the count next door. A drift is a reach that found
# NOTHING; this is a reach that found more than a turn can answer, and adding
# the two together would produce a number that is neither.
class Playthrough::OverreachTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @playthrough = create(:playthrough, story: @story)
  end

  def record(**attributes)
    Playthrough::Overreach.record(
      playthrough: @playthrough,
      action: "take",
      command: "pickup the index and the apron",
      acted: "Perrin's private index",
      unacted: "copy-room apron",
      **attributes
    )
  end

  test "the factory builds a valid row" do
    assert_predicate build(:playthrough_overreach), :valid?
    assert_predicate build(:playthrough_overreach, :move), :valid?
    assert_predicate build(:playthrough_overreach, :talk), :valid?
  end

  test "both halves of the line are on the row" do
    overreach = record

    assert_equal "Perrin's private index", overreach.acted
    assert_equal "copy-room apron", overreach.unacted
    assert_equal "take", overreach.action
    assert_equal @playthrough, overreach.playthrough
  end

  test "the scene and the location are optional, and kept when they are there" do
    location = create(:location, story: @story)
    scene = create(:scene, story: @story, location: location)

    assert_predicate record, :valid?
    assert_equal scene, record(scene: scene, location: location).scene
    assert_equal location, record(scene: scene, location: location).location
  end

  # A LOOK CAN OVERREACH AND IT CANNOT DRIFT, which is why these two lists stopped
  # being the same one. `examine` resolves a record since `ta-item-inscriptions`
  # -- against both item sets at once -- so "read the note and the index" names
  # two things the records have and is refused like any other two-act line;
  # without the value here the row would have failed its own validation and the
  # refusal would have fired uncounted. An `examine` that lands on nothing is
  # still not a drift: it was not reaching for a record it could miss.
  test "the action has to be one the loop resolves against a closed set" do
    assert_not_nil record(action: "examine"), "a look resolves a record, so it can name two"
    assert_nil record(action: "sing")
    assert_nil record(action: "other"), "other resolves to no record at all"

    assert_not_nil record(action: "attack"), "two people hit on one line is two acts like any other"

    assert_equal %w[move talk take drop attack examine], Playthrough::Overreach::ACTIONS
    assert_equal Playthrough::Drift::ACTIONS + %w[examine], Playthrough::Overreach::ACTIONS
    assert_not_includes Playthrough::Drift::ACTIONS, "examine"
    assert_includes Playthrough::Drift::ACTIONS, "attack",
                    "an attack reaches a closed set, so it can miss one as well as name two of it"
  end

  test "a row with nothing on either side of the line is not a measurement" do
    assert_nil record(acted: "")
    assert_nil record(unacted: "")
    assert_nil record(command: "")
  end

  # THE GUARANTEE THIS CLASS STANDS ON, the same one `Playthrough::Drift` has:
  # a measurement taken alongside a turn the player is waiting on must not be
  # able to fail that turn.
  test "a row that cannot be written logs and returns nil rather than raising" do
    assert_nothing_raised do
      assert_nil record(action: nil)
    end
  end

  test "it counts per action, for a story or across the database" do
    create(:playthrough_overreach, playthrough: @playthrough)
    create(:playthrough_overreach, :move, playthrough: @playthrough)
    create(:playthrough_overreach, :move, playthrough: @playthrough)

    assert_equal({ "take" => 1, "move" => 2 }, Playthrough::Overreach.tally(@playthrough.overreaches))
    assert_equal 3, Playthrough::Overreach.for_story(@story).count
  end

  test "another story's rows are not this story's" do
    create(:playthrough_overreach, playthrough: create(:playthrough))
    create(:playthrough_overreach, playthrough: @playthrough)

    assert_equal 1, Playthrough::Overreach.for_story(@story).count
  end

  test "story order is the story's clock and not the wall clock" do
    late = create(:playthrough_overreach, playthrough: @playthrough, story_timestamp: 2.days.from_now)
    early = create(:playthrough_overreach, playthrough: @playthrough, story_timestamp: 1.day.ago)

    assert_equal [ early, late ], Playthrough::Overreach.in_story_order.to_a
  end

  # Not pruned with the conversations, and destroyed with the playthrough it
  # belongs to -- the measurement outlives the audit trail, not the game.
  test "it goes when the playthrough goes" do
    create(:playthrough_overreach, playthrough: @playthrough)

    assert_difference "Playthrough::Overreach.count", -1 do
      @playthrough.destroy!
    end
  end
end
