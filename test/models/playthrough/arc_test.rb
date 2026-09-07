require "test_helper"

# THE FOUR TRIGGERS, READ OFF RECORDS, AND THE ENDING THEY LEAD TO.
#
# These pin the standing constraint applied to plot: a beat is reached because
# the app read a row, never because a model said so -- so every one of them is
# driven by writing the record the game would have written and asking.
#
# AND THE LAYER SPLIT, which is the other half: one player's beat is invisible
# to another player of the same world.
class Playthrough::ArcTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @gate = create(:location, :realized, story: @story, name: "Iron Gate Chamber")
    @cell = create(:location, :realized, story: @story, name: "the dry cell")
    @prince = create(:character, story: @story, fullname: "Prince Aurel Durn", location: @cell)
    @player = create(:character, :protagonist, story: @story)
    @game = create(:playthrough, story: @story, character: @player, current_location: @gate)

    @quest = create(:quest, story: @story, title: "The Long Way Down")
    create(:quest_outcome, :default, quest: @quest, name: "rescued",
                                     summary: "The prince is carried back through the iron gate alive.")
  end

  def arc = Playthrough::Arc.new(@game)

  # --- reach_location --------------------------------------------------------

  test "a reach_location beat is reached by standing in the room" do
    step = bound_step(:reach_location, @cell, "Reach the cell.")

    assert_not arc.reached?(step)

    @game.update!(current_location: @cell)

    assert arc.reached?(step)
  end

  test "an unbound step is never reached, whatever the world happens to contain" do
    step = create(:quest_step, :reach_location, quest: @quest, position: 1, target_name: "the dry cell")
    @game.update!(current_location: @cell)

    assert_predicate step, :unbound?
    assert_not arc.reached?(step)
  end

  test "a place with an inside is reached by walking into its entry room" do
    warren = create(:location, story: @story, name: "Blackfang Warren", width: 12, depth: 10)
    Location::Interior.lay_out!(warren)
    step = bound_step(:reach_location, warren, "Get inside the warren.")

    @game.update!(current_location: Location::Interior.entry_room(warren.reload))

    assert arc.reached?(step)
  end

  # --- speak_to --------------------------------------------------------------

  test "a speak_to beat is reached by the interaction the turn wrote" do
    step = bound_step(:speak_to, @prince, "Ask him what happened.")
    scene = create(:scene, story: @story, location: @cell)
    @game.update!(current_location: @cell, current_scene: scene)

    assert_not arc.reached?(step)

    create(:interaction, character: @prince, scene: scene, location: @cell)

    assert arc.reached?(step)
  end

  test "speaking to somebody else does not reach the beat" do
    step = bound_step(:speak_to, @prince, "Ask him what happened.")
    scene = create(:scene, story: @story, location: @cell)
    @game.update!(current_scene: scene)
    create(:interaction, character: create(:character, story: @story), scene: scene, location: @cell)

    assert_not arc.reached?(step)
  end

  # --- hold_item -------------------------------------------------------------

  test "a hold_item beat is reached by this game's own copy being in the party's hands" do
    key = create(:item, :lying, name: "the cell key", location: @gate)
    step = bound_step(:hold_item, key, "Take the key.")

    assert_not arc.reached?(step)

    create(:item, :carried, name: "the cell key", playthrough: @game, template: key)

    assert arc.reached?(step)
  end

  test "the world's own row lying in a room does not reach a hold_item beat" do
    key = create(:item, :lying, name: "the cell key", location: @gate)
    step = bound_step(:hold_item, key, "Take the key.")

    assert_not arc.reached?(step)
  end

  # --- time_passed -----------------------------------------------------------

  test "a time_passed beat is reached off this game's own clock" do
    step = create(:quest_step, quest: @quest, position: 1, minutes: 40, summary: "Wait it out.")
    @game.update!(current_scene: create(:scene, story: @story, location: @gate,
                                                story_timestamp: @story.start_time + 10.minutes))

    assert_not arc.reached?(step)

    @game.update!(current_scene: create(:scene, story: @story, location: @gate,
                                                story_timestamp: @story.start_time + 40.minutes))

    assert arc.reached?(step)
  end

  # --- the beats are per game ------------------------------------------------

  test "one player's beat is invisible to another player of the same world" do
    step = bound_step(:reach_location, @cell, "Reach the cell.")
    second = create(:playthrough, story: @story, character: @player, current_location: @gate)

    @game.update!(current_location: @cell)
    arc.run!

    assert_equal [ step ], @game.beats.map(&:quest_step)
    assert_empty second.beats
    assert_equal step, @quest.next_step_for(second)
  end

  test "a beat is written once, however many turns stand in the room" do
    bound_step(:reach_location, @cell, "Reach the cell.")
    @game.update!(current_location: @cell)

    assert_difference "Playthrough::Beat.count", 1 do
      3.times { arc.run! }
    end
  end

  test "reached_at is story time and not the wall clock" do
    bound_step(:reach_location, @cell, "Reach the cell.")
    @game.update!(current_location: @cell,
                  current_scene: create(:scene, story: @story, location: @cell,
                                                story_timestamp: @story.start_time + 3.hours))

    arc.run!

    assert_equal @story.start_time + 3.hours, @game.beats.first.reached_at
  end

  # --- the ending ------------------------------------------------------------

  test "reaching the last beat ends the playthrough with the stored sentence" do
    bound_step(:reach_location, @cell, "Reach the cell.")
    @game.update!(current_location: @cell)

    arc.run!

    assert_predicate @game.reload, :over?
    assert_equal "rescued", arc.ending.quest_outcome.name
    closing = @game.current_scene

    assert_equal "conclude", closing.resolved_action
    assert_predicate closing, :engine_authored?
    assert_equal "The prince is carried back through the iron gate alive.", closing.description
  end

  test "an arc with beats left does not end anything" do
    bound_step(:reach_location, @cell, "Reach the cell.", position: 1)
    create(:quest_step, quest: @quest, position: 2, minutes: 600, summary: "And get out again.")
    @game.update!(current_location: @cell)

    arc.run!

    assert_not_predicate @game.reload, :over?
    assert_nil arc.ending
  end

  test "an arc with no ending to reach closes nothing" do
    @quest.outcomes.destroy_all
    bound_step(:reach_location, @cell, "Reach the cell.")
    @game.update!(current_location: @cell)

    arc.run!

    assert_not_predicate @game.reload, :over?
  end

  # --- failure ---------------------------------------------------------------

  test "a game that ends short of the arc writes a failed-quest event" do
    bound_step(:reach_location, @cell, "Reach the cell.")
    @game.end!

    assert_difference "WorldEvent.count", 1 do
      arc.run!
    end

    event = WorldEvent.last

    assert_predicate event, :from_a_quest?
    assert_equal @game, event.playthrough
    assert_nil event.world_mechanic
    assert_includes event.summary, "Reach the cell."
  end

  test "the failure is written once" do
    bound_step(:reach_location, @cell, "Reach the cell.")
    @game.end!

    assert_difference "WorldEvent.count", 1 do
      3.times { arc.run! }
    end
  end

  test "a game that FINISHED the arc and then ended writes no failure" do
    bound_step(:reach_location, @cell, "Reach the cell.")
    @game.update!(current_location: @cell)
    arc.run!

    assert_no_difference "WorldEvent.count" do
      Playthrough::Arc.new(@game.reload).run!
    end
  end

  # A dead player has not finished the arc, they have failed it -- which is why
  # the over? guard comes before the beats rather than after them.
  test "dying on the very turn the last beat would have landed is a failure" do
    bound_step(:reach_location, @cell, "Reach the cell.")
    @game.update!(current_location: @cell)
    @game.end!

    arc.run!

    assert_empty @game.beats
    assert_nil arc.ending
    assert_equal 1, WorldEvent.from_quests.count
  end

  # --- what the narrator is told ---------------------------------------------

  test "the next open step is one line and never the conclusion" do
    first = bound_step(:reach_location, @cell, "Reach the cell.", position: 1)
    create(:quest_step, quest: @quest, position: 2, minutes: 600, summary: "And get out again.")

    assert_equal first, arc.next_step

    @game.update!(current_location: @cell)
    arc.run!

    assert_equal "And get out again.", Playthrough::Arc.new(@game.reload).next_step.summary
  end

  test "a doomed arc tells the narrator nothing" do
    @quest.update!(status: "doomed")
    bound_step(:reach_location, @cell, "Reach the cell.")

    assert_nil arc.next_step
  end

  # --- a world with no arc ---------------------------------------------------

  test "a story with no arc writes nothing and answers nothing" do
    @quest.destroy
    empty = Playthrough::Arc.new(@game.reload)

    assert_equal [], empty.run!
    assert_nil empty.next_step
    assert_nil empty.ending
  end

  private

  def bound_step(kind, record, summary, position: 1)
    step = create(:quest_step, kind, quest: @quest, position: position, summary: summary,
                                     target_name: record.is_a?(Character) ? record.fullname : record.name)
    step.bind!(record, at: @story.start_time)
    @quest.reload
    step
  end
end
