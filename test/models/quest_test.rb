require "test_helper"

# THE WORLD'S OWN ARC.
#
# What these pin is the line between the world and a game: a quest belongs to
# the STORY, and every question about how far somebody got is asked with a
# playthrough in hand. And the two rules that make "the main arc" a phrase
# rather than a guess -- one per story, and a side quest is a child.
class QuestTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @quest = create(:quest, story: @story, title: "The Long Way Down")
  end

  # --- the main arc ----------------------------------------------------------

  test "a quest with no parent is the main arc" do
    assert_predicate @quest, :main?
    assert_equal @quest, Quest.main_arc(@story)
    assert_equal @quest, @story.main_quest
  end

  test "a story cannot have two main arcs" do
    second = build(:quest, story: @story, title: "Another Way Down")

    assert_not second.valid?
    assert_includes second.errors.full_messages.join, "already has one"
  end

  test "a side quest is a child and does not contest the main arc" do
    side = create(:quest, story: @story, title: "The Locksmith's Debt", parent_quest: @quest)

    assert_not side.main?
    assert_equal @quest, Quest.main_arc(@story)
    assert_equal [ side ], @quest.child_quests.to_a
  end

  test "a parent from another story is refused" do
    elsewhere = create(:quest, story: create(:story))
    side = build(:quest, story: @story, parent_quest: elsewhere)

    assert_not side.valid?
    assert_includes side.errors.full_messages.join, "same story"
  end

  # --- the endings, which are rows and not a column ---------------------------

  test "the conclusion is the default outcome's sentence" do
    create(:quest_outcome, quest: @quest, name: "too-late", summary: "The gate closes on both of you.")
    create(:quest_outcome, :default, quest: @quest, name: "rescued",
                                     summary: "The prince is carried back through the iron gate alive.")

    assert_equal "The prince is carried back through the iron gate alive.", @quest.conclusion
    assert_equal "The prince is carried back through the iron gate alive.", @story.conclusion
  end

  test "several endings can exist and only one is the default" do
    create(:quest_outcome, :default, quest: @quest, name: "rescued")
    create(:quest_outcome, quest: @quest, name: "too-late", summary: "You are three days late.")

    assert_equal 2, @quest.outcomes.count
    assert_equal "rescued", @quest.default_outcome.name
  end

  # A world may legitimately have an arc nobody marked a default on -- it is
  # what `rake game:doctor` reports rather than what a load refuses -- so the
  # reader answers the first rather than nothing.
  test "an arc with no default reads its first ending" do
    first = create(:quest_outcome, quest: @quest, name: "one")
    create(:quest_outcome, quest: @quest, name: "two")

    assert_equal first, @quest.default_outcome
  end

  test "a story with no arc has no conclusion and says so with nil" do
    assert_nil create(:story).conclusion
  end

  # --- how far somebody got is asked with a game in hand ----------------------

  test "the next open step is per playthrough" do
    first = create(:quest_step, quest: @quest, position: 1, summary: "Take the ring.")
    second = create(:quest_step, quest: @quest, position: 2, summary: "Get below.")
    ahead = create(:playthrough, story: @story)
    behind = create(:playthrough, story: @story)
    create(:playthrough_beat, playthrough: ahead, quest_step: first)

    assert_equal second, @quest.next_step_for(ahead)
    assert_equal first, @quest.next_step_for(behind)
  end

  # Steps may be satisfied OUT of order, so "next" is the lowest-numbered one
  # nobody has reached rather than the one after the last that was.
  test "the next open step is the lowest unreached position, not the one after the last reached" do
    first = create(:quest_step, quest: @quest, position: 1)
    second = create(:quest_step, quest: @quest, position: 2)
    game = create(:playthrough, story: @story)
    create(:playthrough_beat, playthrough: game, quest_step: second)

    assert_equal first, @quest.next_step_for(game)
  end

  test "an arc is finished when every beat is reached, and only then" do
    step = create(:quest_step, quest: @quest, position: 1)
    game = create(:playthrough, story: @story)

    assert_not @quest.finished_by?(game)

    create(:playthrough_beat, playthrough: game, quest_step: step)
    @quest.reload

    assert @quest.finished_by?(game)
  end

  test "an arc with no beats is never finished" do
    assert_not @quest.finished_by?(create(:playthrough, story: @story))
  end

  # --- what the world says about itself --------------------------------------

  test "status is a closed list and origin says which path wrote it" do
    assert_not build(:quest, story: create(:story), status: "finished").valid?
    assert_not build(:quest, story: create(:story), origin: "wished-for").valid?
    assert_predicate create(:quest, :generated, story: create(:story)), :generated?
  end

  test "destroying a story takes its arc, its beats and its endings" do
    create(:quest_step, quest: @quest, position: 1)
    create(:quest_outcome, quest: @quest, name: "rescued")

    assert_difference [ "Quest.count", "Quest::Step.count", "Quest::Outcome.count" ], -1 do
      @story.destroy
    end
  end
end
