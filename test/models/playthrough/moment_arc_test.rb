require "test_helper"

# THE ONE LINE THE NARRATOR IS EVER TOLD ABOUT THE ARC, and the record-only
# checks that judge it -- because `rake eval:prompt` provably cannot.
#
# WHY THE BENCH CANNOT JUDGE THIS, stated here because it is the reason these
# tests carry the whole weight. The prompt bench's corpus plays two worlds --
# `The Salt Assizes` and `The Unrecorded Hour` -- and neither has a `quests:`
# block, so `Playthrough::Arc#next_step` is nil for all ninety cases and this
# line never renders. Measured rather than assumed: the narrator context for
# every one of those cases is byte-for-byte identical either side of the change,
# and `#the_bench_corpus_worlds_send_an_unchanged_context` below is that fact as
# a test. Buying a bench round would have compared two identical prompts.
#
# SO WHAT IS ASSERTED HERE IS EVERY BRANCH OF THE LINE, on records: that it
# appears exactly once when there is a beat, carries the beat's own summary and
# nothing else, moves on as beats are reached, goes silent when the arc is done,
# and never reaches an NPC.
class Playthrough::MomentArcTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @gate = create(:location, :realized, story: @story, name: "Iron Gate Chamber")
    @cell = create(:location, :realized, story: @story, name: "the dry cell")
    @player = create(:character, :protagonist, story: @story)
    @game = create(:playthrough, story: @story, character: @player, current_location: @gate)
  end

  def context = Playthrough::Moment.new(@game.reload).narration_context

  def arc_lines(text = context) = text.lines.grep(/The story is asking for/)

  # --- a world with no arc is untouched --------------------------------------

  test "a world with no arc says nothing about one" do
    assert_empty arc_lines
  end

  # THE MEASUREMENT THE BENCH WOULD HAVE BOUGHT, made offline. Both worlds the
  # prompt corpus plays are seeded worlds with no `quests:` block, so the line
  # cannot render for any case in it -- which is what makes the stored baseline
  # `prompt-2026-09-05` still a baseline for the prompt this tree sends.
  test "the bench corpus worlds send an unchanged context" do
    # THE WORLDS THE NINETY-CASE CORPUS ACTUALLY PLAYS, off the corpus itself
    # rather than off `Eval::Prompt::STORIES` -- that list gained a third world
    # for the ending's own corpus (`Eval::Prompt::CORPORA`), and that world DOES
    # have an arc. The claim here is about the cases `prompt-2026-09-05`
    # measured.
    Eval::Prompt.corpus("main").positions.map(&:story).uniq.each do |title|
      document = WorldSeed.checked_in_document(title)

      assert_not_nil document, "#{title} is not a checked-in world any more, so this check is reading nothing"
      assert_nil document["quests"],
                 "#{title} has an arc now, so the prompt bench CAN see the next-beat line -- " \
                 "the stored baseline is no longer a before side and a round has to be bought"
    end
  end

  # --- with an arc -----------------------------------------------------------

  test "the next open beat is stated, once, in its own words" do
    quest = arc_with("Find the cell they are keeping him in.")

    assert_equal 1, arc_lines.size
    assert_includes context, "The story is asking for: Find the cell they are keeping him in."
    assert_equal quest.steps.first.summary, arc_lines.first[/asking for: (.*)$/, 1].chomp
  end

  test "the conclusion is never in the prompt, which is the railroad by the back door" do
    arc_with("Find the cell they are keeping him in.")

    assert_not_includes context, "carried back through the iron gate alive"
    assert_not_includes context, "The Long Way Down", "the arc's own title is not a fact about this turn either"
  end

  test "it moves to the next beat as beats are reached" do
    quest = arc_with("Take the ring.", "Get below.")
    Playthrough::Beat.reach!(@game, quest.steps.first, at: @story.start_time)

    assert_includes context, "The story is asking for: Get below."
    assert_not_includes context, "Take the ring."
  end

  test "a finished arc says nothing, because there is no next beat" do
    quest = arc_with("Take the ring.")
    Playthrough::Beat.reach!(@game, quest.steps.first, at: @story.start_time)

    assert_empty arc_lines
  end

  test "a doomed arc says nothing" do
    arc_with("Take the ring.").update!(status: "doomed")

    assert_empty arc_lines
  end

  # A beat is per game, so what one narrator is told is not what the other is.
  test "two players of one world are told two different beats" do
    quest = arc_with("Take the ring.", "Get below.")
    second = create(:playthrough, story: @story, character: @player, current_location: @gate)
    Playthrough::Beat.reach!(@game, quest.steps.first, at: @story.start_time)

    assert_includes context, "Get below."
    assert_includes Playthrough::Moment.new(second).narration_context, "Take the ring."
  end

  # --- and how it ended, on the one pass that asks --------------------------
  #
  # THE OTHER SIDE OF `#test_the_conclusion_is_never_in_the_prompt`, and the two
  # are not in tension: the conclusion is withheld from every pass that is
  # narrating a TURN, because a model told how the story ends writes toward it.
  # `Scene::Ending` is narrating the ending itself, and by then the engine has
  # recorded which one and there is no next turn to be written toward anything.

  test "the ending is stated only to a caller that passes one" do
    quest = arc_with("Take the ring.")
    outcome = quest.default_outcome

    assert_empty ending_lines
    assert_equal 1, ending_lines(with_ending(outcome)).size
    assert_includes with_ending(outcome), "The story has ended: #{outcome.summary}"
  end

  test "the ending line carries the reached outcome's own sentence and not the default's" do
    quest = arc_with("Take the ring.")
    other = create(:quest_outcome, :out_of_order, quest: quest, name: "too-late",
                                                  summary: "The cell is opened and the prince is already cold.")

    assert_includes with_ending(other), "The story has ended: #{other.summary}"
    assert_not_includes with_ending(other), quest.default_outcome.summary,
                        "which ending happened is the engine's answer, and the prompt states that one"
  end

  # The two arc lines cannot both appear, and nothing enforces it: a game that
  # reached its ending reached every beat, so there is no next beat to state.
  test "a game that ended is told how and not what to do next" do
    quest = arc_with("Take the ring.")
    Playthrough::Beat.reach!(@game, quest.steps.first, at: @story.start_time)

    text = with_ending(quest.default_outcome)

    assert_empty arc_lines(text)
    assert_equal 1, ending_lines(text).size
  end

  # `arc:` GOVERNS BOTH LINES, which is what keeps the split between the two
  # passes one decision rather than two: a pass that is not told where the story
  # is going is not told how it ended either. Nothing in the app asks for that
  # combination -- `Scene::Ending` is the one caller that passes an ending, and
  # it asks for the whole moment -- and the keyword has to mean one thing.
  test "the pass that is not told the errand is not told the ending" do
    quest = arc_with("Take the ring.")

    text = Playthrough::Moment.new(@game.reload, ending: quest.default_outcome)
                              .narration_context(plan: false, arc: false)

    assert_empty ending_lines(text)
  end

  # --- and nobody in the fiction is told it ----------------------------------

  test "the character pass is not told the player's errand" do
    arc_with("Find the cell they are keeping him in.")

    assert_empty arc_lines(Playthrough::Moment.new(@game.reload).narration_context(plan: false, arc: false))
  end

  test "InteractionAgent asks for the moment without it" do
    arc_with("Find the cell they are keeping him in.")
    someone = create(:character, story: @story, location: @gate)

    section = InteractionAgent.new(someone, playthrough: @game.reload)
                              .send(:narrator_moment_section)

    assert_empty arc_lines(section)
    assert_includes section, "Iron Gate Chamber", "the rest of the moment is unchanged"
  end

  private

  def with_ending(outcome)
    Playthrough::Moment.new(@game.reload, ending: outcome).narration_context
  end

  def ending_lines(text = context) = text.lines.grep(/The story has ended/)

  def arc_with(*summaries)
    quest = create(:quest, story: @story, title: "The Long Way Down")
    create(:quest_outcome, :default, quest: quest, name: "rescued",
                                     summary: "The prince is carried back through the iron gate alive.")

    summaries.each_with_index do |summary, index|
      step = create(:quest_step, :reach_location, quest: quest, position: index + 1,
                                 summary: summary, target_name: @cell.name)
      step.bind!(@cell, at: @story.start_time)
    end

    quest
  end
end
