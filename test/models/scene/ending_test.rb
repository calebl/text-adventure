require "test_helper"

# THE LAST PARAGRAPH, AND THE SENTENCE UNDERNEATH IT.
#
# `Playthrough::ArcOutcomeTest` pins which ending a game reaches and
# `Playthrough::TurnEndingTest` pins the turn that renders one. This is the
# pass itself: what it is told, what it writes, and -- most of the tests here --
# what a game is left with when the call does not come back.
#
# EVERY FALLBACK CASE IS ONE ASSERTION MADE FOUR WAYS, on purpose. A refusal, a
# suppressed crisis response, a dropped connection and a paragraph cut in half
# are four different failures with one required outcome: the player still has an
# ending, and it is the engine's own sentence.
class Scene::EndingTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @cell = create(:location, :realized, story: @story, name: "the dry cell")
    @player = create(:character, :protagonist, story: @story)
    @game = create(:playthrough, story: @story, character: @player, current_location: @cell)

    @quest = create(:quest, story: @story, title: "The Long Way Down")
    @outcome = create(:quest_outcome, :default, quest: @quest, name: "rescued",
                                                summary: "The prince walks out through the iron gate alive.")
  end

  # --- what it writes --------------------------------------------------------

  test "the narrated ending replaces the engine's sentence on the closing scene" do
    conclusion = conclude!
    prose = "The gate grinds up, and the light on the other side is the first you have seen in days."

    scene = narrate(conclusion, prose)

    assert_equal conclusion.scene, scene, "one row carries the last paragraph, whoever wrote it"
    assert_equal prose, scene.description
    assert_equal scene, @game.reload.current_scene
  end

  # The label is what `Scene#engine_authored?` reads, so it is the whole of what
  # tells `Story::Audit` and `Eval::Richness` that this row is prose to be read
  # rather than the app's own copy to be skipped.
  test "a rendered ending is labelled as narration and an unrendered one stays the engine's" do
    rendered = narrate(conclude!, "The gate grinds up and the daylight takes him.")

    assert_equal Scene::NARRATED_ENDING, rendered.resolved_action
    assert_not_predicate rendered, :engine_authored?
    assert_predicate rendered, :ending?

    setup
    fell_back = narrate(conclude!, BaseAgent::RefusalError)

    assert_equal "conclude", fell_back.resolved_action
    assert_predicate fell_back, :engine_authored?
    assert_predicate fell_back, :ending?
  end

  test "the engine's sentence survives the paragraph that replaced it" do
    scene = narrate(conclude!, "The gate grinds up and the daylight takes him.")

    assert_equal @outcome.summary, scene.summary
    assert_equal @outcome.summary, Scene.recap_line(scene),
                 "a turn's one line of memory is the engine's fact, not the prose about it"
  end

  test "it streams the ending the way a turn streams" do
    chunks = []
    narrate(conclude!, "The gate grinds up and the daylight takes him.") { |chunk| chunks << chunk }

    assert_operator chunks.length, :>, 1
    assert_equal "The gate grinds up and the daylight takes him.", chunks.join
  end

  test "the call is unschema'd, exactly as the narrator's is" do
    agent = FakeAgent.new("The gate grinds up and the daylight takes him.")
    BaseAgent.stub(:new, agent) { Scene::Ending.new(@game).narrate!(conclude!) }

    assert_empty agent.schemas
  end

  # --- what it is told ------------------------------------------------------

  test "it is told the reached outcome's own sentence as a fact" do
    agent = FakeAgent.new("The gate grinds up.")
    BaseAgent.stub(:new, agent) { Scene::Ending.new(@game).narrate!(conclude!) }

    assert_match "The story has ended: #{@outcome.summary}", agent.prompts.first
    assert_match @cell.name, agent.prompts.first
    assert_match "Write the ending.", agent.prompts.first
  end

  # The closing Scene's own description IS the stored sentence, and
  # `playthrough.current_scene` is pointing at it by the time this pass runs. So
  # *what just happened* has to step back one, or the prompt states the engine's
  # sentence twice and invites the model to hand it straight back.
  test "what just happened is the turn the player took, not the sentence being rendered" do
    @game.update!(current_scene: create(:scene, story: @story, location: @cell,
                                                description: "You put your shoulder to the cell door."))
    agent = FakeAgent.new("The gate grinds up.")
    BaseAgent.stub(:new, agent) { Scene::Ending.new(@game).narrate!(conclude!) }

    prompt = agent.prompts.first

    assert_match "What just happened: You put your shoulder to the cell door.", prompt
    assert_equal 1, prompt.scan(@outcome.summary).size, "the ending is stated once, as a fact"
  end

  # --- and every way it can fail --------------------------------------------

  test "a refusal leaves the engine's sentence standing" do
    scene = narrate(conclude!, BaseAgent::RefusalError)

    assert_equal @outcome.summary, scene.description
    assert_equal scene, @game.reload.current_scene
    assert_predicate @game, :over?
  end

  # `NarrationJob` answers a crisis response by showing the safety notice
  # INSTEAD of the turn. On this turn that would take the ending off the page
  # with the suppressed text, so it is caught here.
  test "a suppressed crisis response leaves the engine's sentence standing" do
    scene = narrate(conclude!, BaseAgent::CrisisResponseError)

    assert_equal @outcome.summary, scene.description
  end

  test "a dropped call leaves the engine's sentence standing" do
    scene = narrate(conclude!, Timeout::Error)

    assert_equal @outcome.summary, scene.description
  end

  test "an answer with nothing in it leaves the engine's sentence standing" do
    scene = narrate(conclude!, "   ")

    assert_equal @outcome.summary, scene.description
  end

  # `Scene::Narrator` keeps a truncated turn -- the player can type again.
  # Nobody types again after this one, so a paragraph that stops mid-sentence is
  # worse than the complete sentence the engine is already holding.
  test "a paragraph cut in half is not kept" do
    scene = narrate(conclude!, "The gate grinds up and the light on the other side is the")

    assert_equal @outcome.summary, scene.description
    assert_equal "conclude", scene.resolved_action
  end

  # --- what this pass is measured by, and what it must not have moved --------
  #
  # THE ENDING HAS ITS OWN BENCH: `test/fixtures/files/prompt_ending_corpus.yml`,
  # played over the one world with an arc, with both sides checked in under
  # `db/eval/prompt-ending-*-2026-09-08` -- see EVALUATION.md and
  # `Eval::Prompt::EndingKeptSetTest`. What it deliberately did NOT do is touch
  # the ninety-case corpus, because `Eval::Prompt.digest` is over the cases and
  # the 2026-09-05 baseline is the before side for the prompts those cases send.
  #
  # SO THIS IS THE CANARY ON THE OTHER CORPUS. None of the worlds it plays has an
  # arc, which is why no case in it could conclude one, reach this pass, or so
  # much as gain a line -- and the day one of them gains a `quests:` block, that
  # is no longer true and its baseline needs re-taking.

  test "the ninety-case corpus still cannot reach an ending, so its baseline stands" do
    Eval::Prompt.corpus("main").positions.map(&:story).uniq.each do |title|
      document = WorldSeed.checked_in_document(title)

      assert_not_nil document, "#{title} is not a checked-in world any more, so this check is reading nothing"
      assert_nil document["quests"],
                 "#{title} has an arc now, so a case in the main corpus CAN end a game and reach " \
                 "Scene::Ending -- its prompts have moved and prompt-2026-09-05 is no longer their before side"
    end
  end

  # AND THE OTHER HALF OF THE SAME ARGUMENT: the prompt every other pass sends
  # is what it was, so the checked-in prompt baseline is still a baseline for it.
  # The ending line is guarded on a caller passing an outcome and there is
  # exactly one caller that does, which is what this pins -- a game can be over,
  # with an ending on record, and any other pass's moment still does not mention
  # it.
  test "the ending is stated to the pass that asks for it and to nothing else" do
    conclude!

    assert_not_includes Playthrough::Moment.new(@game.reload).narration_context, "The story has ended"
    assert_includes Playthrough::Moment.new(@game.reload, ending: @outcome).narration_context,
                    "The story has ended: #{@outcome.summary}"
  end

  private

  # The engine's half, run for real: the beat lands, the arc selects the
  # outcome, and the closing Scene is written with the sentence already on it.
  def conclude!
    step = create(:quest_step, :reach_location, quest: @quest, position: 1,
                                                summary: "Find the cell.", target_name: @cell.name)
    step.bind!(@cell, at: @story.start_time)
    @quest.reload

    arc = Playthrough::Arc.new(@game.reload)
    arc.run!
    arc.conclusion
  end

  def narrate(conclusion, answer, &block)
    BaseAgent.stub(:new, FakeAgent.new(answer)) do
      Scene::Ending.new(@game).narrate!(conclusion, &block)
    end
  end
end
