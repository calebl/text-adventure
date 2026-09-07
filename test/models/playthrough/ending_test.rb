require "test_helper"

# WHICH ENDING ONE GAME REACHED. `Playthrough::Beat`'s argument one table over,
# plus the rule that has no counterpart there: an arc ends once, so one game
# cannot reach two endings of one quest.
class Playthrough::EndingTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @quest = create(:quest, story: @story)
    @rescued = create(:quest_outcome, :default, quest: @quest, name: "rescued")
    @too_late = create(:quest_outcome, quest: @quest, name: "too-late", summary: "Three days late.")
    @game = create(:playthrough, story: @story)
  end

  test "one game reaches one ending of one arc" do
    create(:playthrough_ending, playthrough: @game, quest_outcome: @rescued)

    second = build(:playthrough_ending, playthrough: @game, quest_outcome: @too_late)

    assert_not second.valid?
    assert_includes second.errors.full_messages.join, "already finished"
  end

  test "a second arc's ending is a different arc and is allowed" do
    side = create(:quest, story: @story, title: "The Locksmith's Debt", parent_quest: @quest)
    paid = create(:quest_outcome, quest: side, name: "paid")
    create(:playthrough_ending, playthrough: @game, quest_outcome: @rescued)

    assert build(:playthrough_ending, playthrough: @game, quest_outcome: paid).valid?
  end

  test "two games of one world reach their own endings" do
    second = create(:playthrough, story: @story)
    create(:playthrough_ending, playthrough: @game, quest_outcome: @rescued)
    create(:playthrough_ending, playthrough: second, quest_outcome: @too_late)

    assert_equal 2, Playthrough::Ending.count
  end

  test "an ending from another story is refused" do
    elsewhere = create(:quest_outcome, quest: create(:quest, story: create(:story)))

    assert_not build(:playthrough_ending, playthrough: @game, quest_outcome: elsewhere).valid?
  end
end
