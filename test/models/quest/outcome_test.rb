require "test_helper"

# ONE WAY AN ARC CAN END. Several per quest, on the captain's note of
# 2026-09-06, keyed on a short name so a seed file can re-assert one.
class Quest::OutcomeTest < ActiveSupport::TestCase
  def setup
    @quest = create(:quest, story: create(:story))
  end

  test "a quest may have several endings" do
    create(:quest_outcome, :default, quest: @quest, name: "rescued")
    create(:quest_outcome, quest: @quest, name: "too-late", summary: "You are three days late.")

    assert_equal %w[rescued too-late], @quest.outcomes.map(&:name).sort
  end

  test "a name is unique within its quest and free across quests" do
    create(:quest_outcome, quest: @quest, name: "rescued")

    assert_not build(:quest_outcome, quest: @quest, name: "rescued").valid?
    assert build(:quest_outcome, quest: create(:quest, story: create(:story)), name: "rescued").valid?
  end

  test "an ending is a sentence and refuses to be nothing" do
    assert_not build(:quest_outcome, quest: @quest, summary: "").valid?
  end

  test "the default is not a claim that the ending is a good one" do
    bleak = create(:quest_outcome, :default, quest: @quest, name: "the-gate-holds",
                                             summary: "The gate holds, and nobody comes back up.")

    assert_equal bleak, @quest.default_outcome
    assert_equal "The gate holds, and nobody comes back up.", @quest.conclusion
  end
end
