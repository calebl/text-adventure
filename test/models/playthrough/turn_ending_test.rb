require "test_helper"

# THE ENDING IN THE BROWSER'S LOOP: the turn that ends the story, end to end.
#
# `Scene::EndingTest` is the prose pass on its own and `Playthrough::ArcOutcomeTest`
# is which ending a game reaches. This is the seam between them -- the one place
# in the app where a model is asked about an ending at all -- and the three
# things about it that could break without either of those files noticing:
#
#   THE CALL IS MADE ONLY ON THE TURN THE ARC CONCLUDED. One FakeAgent stands in
#   for every BaseAgent the turn builds, so the queued answers ARE the calls the
#   turn is allowed to make, in order. An ordinary turn that reached for an
#   ending narrator would run out of answers and fail here loudly.
#   THE TURN ANSWERS WITH THE ENDING. `NarrationJob` broadcasts the log off the
#   playthrough, and what `#play` returns is what a consumer is holding: on this
#   one turn the story's last paragraph, and not the second-to-last thing the
#   game will ever say.
#   AND THE FALLBACK IS REACHED THROUGH THE LOOP, not only through the pass: a
#   game whose ending call refused is over, with words, and the words are the
#   engine's.
class Playthrough::TurnEndingTest < ActiveSupport::TestCase
  CLASSIFY = ->(intent, target) { { "intent" => intent, "target" => target } }

  def setup
    @story = create(:story)
    @vance = create(:character, :protagonist, story: @story, fullname: "Odile Vance")
    @cell = create(:location, :realized, story: @story, name: "the dry cell")
    @playthrough = create(:playthrough, story: @story, character: @vance, current_location: @cell)
    # THE WORLD'S OWN ROW, not this game's copy: a `hold_item` beat is bound to
    # the template and reached by the copy `Item::Snapshot` makes on the turn
    # (`Playthrough::Arc#holding?`), which is the layer split the turn walks
    # through for real here.
    @ring = create(:item, :lying, location: @cell, name: "signet ring")

    @quest = create(:quest, story: @story, title: "The Long Way Down")
    @outcome = create(:quest_outcome, :default, quest: @quest, name: "rescued",
                                                summary: "The prince walks out through the iron gate alive.")
  end

  # --- the turn that ends the story -----------------------------------------

  test "the last beat is taken, and the turn answers with the ending in words" do
    beat_wanting_the_ring!

    scene, agent = play("take the ring",
                        CLASSIFY.call("take", "signet ring"),
                        "You lift the ring out of the mud.",
                        "The gate grinds up, and the light on the far side is the first in days.")

    assert_equal "The gate grinds up, and the light on the far side is the first in days.", scene.description
    assert_equal Scene::NARRATED_ENDING, scene.resolved_action
    assert_equal scene, @playthrough.reload.current_scene
    assert_predicate @playthrough, :over?
    assert_equal @outcome, Playthrough::Arc.new(@playthrough).ending.quest_outcome
    assert_equal 3, agent.prompts.size, "the classifier, the take's own prose, and the ending"
  end

  test "the ending is told the outcome the engine selected" do
    beat_wanting_the_ring!

    _scene, agent = play("take the ring",
                         CLASSIFY.call("take", "signet ring"),
                         "You lift the ring out of the mud.",
                         "The gate grinds up and the daylight takes him.")

    assert_match "The story has ended: #{@outcome.summary}", agent.prompts.last
  end

  # The take's own paragraph is still the take's own paragraph: the ending is a
  # second Scene of the same turn, and the turn's prose is not overwritten by it.
  test "the turn's own prose survives the ending that follows it" do
    beat_wanting_the_ring!

    scene, = play("take the ring",
                  CLASSIFY.call("take", "signet ring"),
                  "You lift the ring out of the mud.",
                  "The gate grinds up and the daylight takes him.")

    assert_equal "You lift the ring out of the mud.", scene.previous_scene.description
    assert_equal "take", scene.previous_scene.resolved_action
  end

  test "a refused ending call still ends the game with the engine's own sentence" do
    beat_wanting_the_ring!

    scene, = play("take the ring",
                  CLASSIFY.call("take", "signet ring"),
                  "You lift the ring out of the mud.",
                  BaseAgent::RefusalError)

    assert_equal @outcome.summary, scene.description
    assert_equal "conclude", scene.resolved_action
    assert_predicate @playthrough.reload, :over?
    assert_equal scene, @playthrough.current_scene
  end

  # --- and every other turn -------------------------------------------------

  test "a turn that reached no beat buys no ending call" do
    create(:quest_step, :hold_item, quest: @quest, position: 1, summary: "Take the ring.",
                                    target_name: "no such thing")

    scene, agent = play("take the ring",
                        CLASSIFY.call("take", "signet ring"),
                        "You lift the ring out of the mud.")

    assert_equal "You lift the ring out of the mud.", scene.description
    assert_equal 2, agent.prompts.size, "the classifier and the take's own prose, and nothing else"
    assert_not_predicate @playthrough.reload, :over?
  end

  test "a world with no arc at all is untouched" do
    @quest.destroy

    scene, agent = play("take the ring",
                        CLASSIFY.call("take", "signet ring"),
                        "You lift the ring out of the mud.")

    assert_equal "You lift the ring out of the mud.", scene.description
    assert_equal 2, agent.prompts.size
  end

  private

  # One beat, bound to the ring, so picking it up finishes the arc.
  def beat_wanting_the_ring!
    step = create(:quest_step, :hold_item, quest: @quest, position: 1,
                                           summary: "Take the ring.", target_name: @ring.name)
    step.bind!(@ring, at: @story.start_time)
    @quest.reload
  end

  def play(command, *responses)
    agent = FakeAgent.new(*responses)
    outcome = BaseAgent.stub(:new, agent) { Playthrough::Turn.new(@playthrough).play(command) }

    [ outcome, agent ]
  end
end
