require "test_helper"

# WHICH OF SEVERAL ENDINGS ONE GAME REACHED, AND WHAT THE WORLD DOES ABOUT IT.
#
# The captain's note of 2026-09-06: *"multiple endings to a quest must be
# possible. a failed quest gets stored as an event that can have future
# ramifications."* `Playthrough::ArcTest` one file over pins the four triggers
# and the ending being written at all; this pins WHICH one is written, and the
# rows that follow it.
#
# EVERY ONE OF THESE IS DRIVEN BY WRITING THE RECORD THE GAME WOULD HAVE
# WRITTEN AND ASKING -- no model anywhere, which is the standing constraint and
# also the only reason a rule like this can be tested at all.
class Playthrough::ArcOutcomeTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @gate = create(:location, :realized, story: @story, name: "Iron Gate Chamber")
    @cell = create(:location, :realized, story: @story, name: "the dry cell")
    @player = create(:character, :protagonist, story: @story)
    @game = create(:playthrough, story: @story, character: @player, current_location: @gate)

    @quest = create(:quest, story: @story, title: "The Long Way Down")
    @rescued = create(:quest_outcome, :default, quest: @quest, name: "rescued",
                                                summary: "The prince is carried back through the iron gate alive.")
  end

  def arc = Playthrough::Arc.new(@game.reload)

  # --- falling through -------------------------------------------------------

  test "an arc with one ending reaches it" do
    reach_the_cell!

    assert_equal @rescued, arc.ending.quest_outcome
  end

  test "a second ending whose rule does not hold changes nothing" do
    create(:quest_outcome, :slower_than, quest: @quest, name: "too-late", minutes: 600)
    reach_the_cell!

    assert_equal @rescued, arc.ending.quest_outcome
  end

  # A non-default ending with no `condition` is one nothing can select. It is
  # legal (`Story::Doctor` reports it) and it must never win by being listed
  # first, which is what this pins.
  test "an ending nothing selects is never reached, whatever order it is written in" do
    create(:quest_outcome, quest: @quest, name: "unreachable", condition: nil)
    reach_the_cell!

    assert_equal @rescued, arc.ending.quest_outcome
  end

  # --- slower_than -----------------------------------------------------------

  test "a game that ran past the budget reaches the ending that says so" do
    late = create(:quest_outcome, :slower_than, quest: @quest, name: "too-late", minutes: 120)
    reach_the_cell!(at: @story.start_time + 3.hours)

    assert_equal late, arc.ending.quest_outcome
  end

  test "a game that finished on the stroke of the budget was not slower than it" do
    create(:quest_outcome, :slower_than, quest: @quest, name: "too-late", minutes: 120)
    reach_the_cell!(at: @story.start_time + 2.hours)

    assert_equal @rescued, arc.ending.quest_outcome
  end

  # --- out_of_order ----------------------------------------------------------

  test "taking the beats out of the arc's order reaches the ending that says so" do
    wrong_way = create(:quest_outcome, :out_of_order, quest: @quest, name: "the-wrong-way-round")
    step_one = bound_step(:reach_location, @cell, "Find the cell.", position: 1)
    bound_step(:reach_location, @gate, "Stand at the gate.", position: 2)

    # The gate first, which is beat TWO, and the cell after it.
    arc.run!
    @game.update!(current_location: @cell)
    arc.run!

    assert_equal [ 2, 1 ], @game.beats.in_story_order.map { |beat| beat.quest_step.position }
    assert_equal wrong_way, arc.ending.quest_outcome
    assert_equal step_one, @game.beats.in_story_order.last.quest_step
  end

  test "taking them in order falls through to the default" do
    create(:quest_outcome, :out_of_order, quest: @quest, name: "the-wrong-way-round")
    bound_step(:reach_location, @cell, "Find the cell.", position: 1)
    bound_step(:reach_location, @gate, "Stand at the gate.", position: 2)

    @game.update!(current_location: @cell)
    arc.run!
    @game.update!(current_location: @gate)
    arc.run!

    assert_equal @rescued, arc.ending.quest_outcome
  end

  # --- which of two that both hold ------------------------------------------

  test "the first rule the world wrote wins" do
    first = create(:quest_outcome, :slower_than, quest: @quest, name: "too-late", minutes: 60)
    create(:quest_outcome, :out_of_order, quest: @quest, name: "the-wrong-way-round")
    bound_step(:reach_location, @cell, "Find the cell.", position: 1)
    bound_step(:reach_location, @gate, "Stand at the gate.", position: 2)

    @game.update!(current_scene: scene_at(@story.start_time + 5.hours))
    arc.run!
    @game.update!(current_location: @cell)
    arc.run!

    assert_equal first, arc.ending.quest_outcome
  end

  # --- the event a finished arc writes --------------------------------------

  test "finishing the arc writes a quest event carrying the playthrough" do
    reach_the_cell!

    event = WorldEvent.from_quests.sole

    assert_equal @game, event.playthrough
    assert_nil event.world_mechanic
    assert_not_predicate event, :scheduled?
    assert_includes event.summary, "rescued"
    assert_includes event.summary, "The Long Way Down"
  end

  test "one quest event per game, whichever way the game went" do
    reach_the_cell!

    assert_no_difference "WorldEvent.count" do
      3.times { arc.run! }
    end
  end

  # --- the ramification ------------------------------------------------------

  test "an ending with a ramification puts one scheduled row on the stream" do
    @rescued.update!(ramification_minutes: 180,
                     ramification_summary: "The Blackfang bar the low door behind whoever took it.")
    reach_the_cell!(at: @story.start_time + 1.hour)

    row = WorldEvent.pending.sole

    assert_predicate row, :from_a_quest?
    assert_equal @story.start_time + 4.hours, row.scheduled_for
    assert_equal @story.start_time + 1.hour, row.occurred_at
    assert_equal "The Blackfang bar the low door behind whoever took it.", row.summary
  end

  # THE ONE THING ABOUT A RAMIFICATION THAT IS A DECISION RATHER THAN A COLUMN:
  # the game that earned it is over, so a consequence scoped to that game could
  # never arrive. It is the WORLD's.
  test "a ramification carries no playthrough" do
    @rescued.update!(ramification_minutes: 180, ramification_summary: "The low door is barred.")
    reach_the_cell!

    assert_nil WorldEvent.pending.sole.playthrough
  end

  test "an ending with no ramification schedules nothing" do
    reach_the_cell!

    assert_empty WorldEvent.pending
  end

  test "a failure schedules nothing, because it reached no ending" do
    @rescued.update!(ramification_minutes: 180, ramification_summary: "The low door is barred.")
    bound_step(:reach_location, @cell, "Find the cell.")
    @game.end!

    arc.run!

    assert_empty WorldEvent.pending
    assert_equal 1, WorldEvent.from_quests.count
  end

  private

  def scene_at(moment)
    create(:scene, story: @story, location: @game.current_location, story_timestamp: moment)
  end

  def reach_the_cell!(at: nil)
    bound_step(:reach_location, @cell, "Find the cell.")
    @game.update!(current_location: @cell)
    @game.update!(current_scene: scene_at(at)) if at
    arc.run!
  end

  def bound_step(kind, record, summary, position: 1)
    step = create(:quest_step, kind, quest: @quest, position: position, summary: summary,
                                     target_name: record.is_a?(Character) ? record.fullname : record.name)
    step.bind!(record, at: @story.start_time)
    @quest.reload
    step
  end
end
