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

  # --- WHICH OF SEVERAL, AND THE RULE THAT SAYS SO --------------------------

  test "a condition is one of the closed table and nothing else" do
    assert build(:quest_outcome, :slower_than, quest: @quest).valid?
    assert build(:quest_outcome, :out_of_order, quest: @quest).valid?
    assert_not build(:quest_outcome, quest: @quest, condition: "if_the_player_was_brave").valid?
  end

  test "no condition at all is the ordinary state, and it is what the default is" do
    assert build(:quest_outcome, quest: @quest, condition: nil).valid?
    assert_not build(:quest_outcome, quest: @quest, condition: nil).conditional?
  end

  test "the default carries no rule, because falling through is its rule" do
    outcome = build(:quest_outcome, :default, :out_of_order, quest: @quest)

    assert_not outcome.valid?
    assert_includes outcome.errors[:condition],
                    "is the ending the world was built toward, which is what falling through means"
  end

  test "the one rule that takes a number needs it, and the one that does not refuses it" do
    assert_not build(:quest_outcome, quest: @quest, condition: "slower_than", minutes: nil).valid?
    assert_not build(:quest_outcome, quest: @quest, condition: "slower_than", minutes: 0).valid?
    assert_not build(:quest_outcome, quest: @quest, condition: "out_of_order", minutes: 30).valid?
    assert_not build(:quest_outcome, quest: @quest, condition: nil, minutes: 30).valid?
  end

  # --- AND WHAT THE WORLD DOES ABOUT IT AFTERWARDS ---------------------------

  test "a ramification is an hour and a sentence, and half of one is refused" do
    assert build(:quest_outcome, :out_of_order, :with_a_ramification, quest: @quest).valid?
    assert_not build(:quest_outcome, quest: @quest, ramification_minutes: 60).valid?
    assert_not build(:quest_outcome, quest: @quest, ramification_summary: "The door is barred.").valid?
  end

  test "an ending with no ramification schedules nothing" do
    assert_not build(:quest_outcome, quest: @quest).schedules_a_ramification?
    assert build(:quest_outcome, :with_a_ramification, quest: @quest).schedules_a_ramification?
  end
end
