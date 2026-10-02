require "test_helper"

# WHY A PLAYTHROUGH ENDED, DERIVED OFF THE RECORDS.
#
# `playthroughs.ended_at` says a game is over and does not say why, and until
# this class existed nothing asked: a player who finished their story read their
# narrated ending and then, under it, "You are dead." So the statements here are
# the rule itself -- which record answers, in which order, and what a game with
# neither one is shown -- and nothing here reads a word of prose to decide it.
class Playthrough::EndNoticeTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @room = create(:location, story: @story, name: "the dry cell")
    @vance = create(:character, :protagonist, story: @story, fullname: "Odile Vance", location: @room)
    @game = create(:playthrough, story: @story, character: @vance, current_location: @room)
    @quest = create(:quest, story: @story)
    @outcome = create(:quest_outcome, :default, quest: @quest, name: "rescued",
                                                summary: "The prince walks out through the iron gate alive.")
  end

  # --- the rule -------------------------------------------------------------

  test "an ending row means the story concluded" do
    conclude!

    notice = Playthrough::EndNotice.for(@game)

    assert_predicate notice, :concluded?
    assert_not_predicate notice, :died?
    assert_equal :concluded, notice.reason
  end

  test "a protagonist at zero means death" do
    kill!

    notice = Playthrough::EndNotice.for(@game)

    assert_predicate notice, :died?
    assert_not_predicate notice, :concluded?
    assert_equal :died, notice.reason
  end

  # The app cannot write this pair -- `#conclude!` returns nil for a game
  # already over and `#harm!` ends one the moment it takes the last hit point --
  # but a repaired database can, and the ending is what stopped the game.
  test "the ending wins when both records are there" do
    conclude!
    Playthrough::Vitals.find_by(playthrough: @game, character: @vance).update!(hp_current: 0)

    assert_equal :concluded, Playthrough::EndNotice.for(@game).reason
  end

  # A game with no protagonist at all cannot have died, and asking its vitals is
  # what used to be one nil away from an exception.
  test "a game with no protagonist and no ending is unrecorded rather than dead" do
    castless = create(:playthrough, story: @story, character: nil, current_location: @room)
    castless.end!

    assert_equal :unrecorded, Playthrough::EndNotice.for(castless).reason
  end

  # `#died?` used to be `!concluded?`, so it said "died" of a game nobody died in.
  test "an unrecorded game neither concluded nor died" do
    @game.end!

    notice = Playthrough::EndNotice.for(@game)

    assert_not_predicate notice, :concluded?
    assert_not_predicate notice, :died?
  end

  test "an ended game with neither record is unrecorded" do
    @game.end!

    assert_equal :unrecorded, Playthrough::EndNotice.for(@game).reason
  end

  # --- and the copy each of them gets ---------------------------------------

  test "a concluded game is told its story is over and never that it is dead" do
    conclude!

    notice = Playthrough::EndNotice.for(@game)

    assert_equal Playthrough::StoryOverNotice::HEADING, notice.heading
    assert_equal Playthrough::StoryOverNotice::PARAGRAPHS, notice.paragraphs
    assert_no_match(/dead/i, [ notice.heading, *notice.paragraphs, notice.sentence ].join(" "))
    assert_match(/new playthrough/, notice.paragraphs.join(" "))
  end

  test "a death is told the death notice, unchanged" do
    kill!

    notice = Playthrough::EndNotice.for(@game)

    assert_equal Playthrough::DeathNotice::HEADING, notice.heading
    assert_equal Playthrough::DeathNotice::PARAGRAPHS, notice.paragraphs
    assert_match(/Odile Vance is dead/, notice.sentence)
  end

  # THE THIRD SET OF WORDS. A game the records cannot explain used to be shown
  # the death copy -- "You are dead." over a protagonist the records have alive
  # -- and is told only what is on record now; see this class's header.
  test "an unrecorded ending is told the game stopped and never that it is dead or concluded" do
    @game.end!

    notice = Playthrough::EndNotice.for(@game)

    assert_equal Playthrough::StoppedNotice::HEADING, notice.heading
    assert_equal Playthrough::StoppedNotice::PARAGRAPHS, notice.paragraphs
    assert_equal Playthrough::StoppedNotice.sentence(@vance), notice.sentence
    assert_equal :stopped, notice.refusal_kind
    assert_no_match(/dead|is over/i, [ notice.heading, *notice.paragraphs, notice.sentence ].join(" "))
    assert_match(/new playthrough/, notice.paragraphs.join(" "))
    assert_nil notice.closing_words
  end

  test "a game with no protagonist is told the game stopped, addressed to the player" do
    castless = create(:playthrough, story: @story, character: nil, current_location: @room)
    castless.end!

    assert_match(/\AYour story stopped/, Playthrough::EndNotice.for(castless).sentence)
  end

  test "the refusal and the standing notice come out of the same author" do
    conclude!

    notice = Playthrough::EndNotice.for(@game)

    assert_equal :concluded, notice.refusal_kind
    assert_equal Playthrough::StoryOverNotice.sentence(@vance), notice.sentence
  end

  # --- the ending's own last words ------------------------------------------

  # THE ORDINARY FINISHED GAME. The closing `Scene` is the head of the chain and
  # therefore the last entry of the turn log, so the notice must not print the
  # same paragraph a second line below it.
  test "the closing words are nil when the log already carries them" do
    conclude!

    assert_nil Playthrough::EndNotice.for(@game).closing_words
  end

  test "the closing words are the stored outcome sentence when there is no closing scene" do
    create(:playthrough_ending, playthrough: @game, quest_outcome: @outcome)
    @game.end!

    assert_equal @outcome.to_s, Playthrough::EndNotice.for(@game).closing_words
  end

  test "a death has no closing words" do
    kill!

    assert_nil Playthrough::EndNotice.for(@game).closing_words
  end

  test "the ending it names is the one the game reached" do
    conclude!

    assert_equal @outcome, Playthrough::EndNotice.for(@game).ending.quest_outcome
  end

  private

  # THE ROWS `Playthrough::Arc#conclude!` WRITES, in the shape it writes them:
  # the ending, the closing `Scene` carrying the outcome's own sentence, the
  # chain head pointed at it, and `ended_at`.
  # --- which goal, and why this ending ----------------------------------------
  #
  # The owner's game: The Lunar Cartographer closed on a paragraph about a dead
  # man standing, and nothing on the screen said which goal had ended it or why
  # that ending. These are what the notice says instead, off the rows.

  test "a concluded story names its goals, the one met last and why the default" do
    met!(1, 3, 2)
    create(:quest_outcome, :out_of_order, quest: @quest, name: "the-wrong-way-round")
    conclude!

    finished = Playthrough::EndNotice.for(@game).finished

    assert_equal @quest.title, finished.quest
    assert_equal [ "Climb to the bell.", "Get the tally.", "Take the bearing book." ], finished.goals
    assert_equal 2, finished.last_goal
    assert_equal "Goal 2 was the last you met, and it finished the story. None of the story's other endings " \
                 "applied, so this is the one it was built toward.", finished.reason
  end

  test "an ending reached out of order says which goal came first" do
    @outcome = create(:quest_outcome, :out_of_order, quest: @quest, name: "the-wrong-way-round")
    met!(1, 3, 2)
    conclude!

    assert_equal "Goal 2 was the last you met, and it finished the story. You met goal 3 before goal 2, " \
                 "which is what this ending is for.", Playthrough::EndNotice.for(@game).finished.reason
  end

  test "an ending reached while somebody lived names them" do
    ringer = create(:character, story: @story, fullname: "Marek Sollen")
    @outcome = create(:quest_outcome, :while_alive, quest: @quest, name: "taken-under-his-hands",
                                                    step_position: 3, character: ringer)
    met!(1, 3, 2)
    conclude!

    assert_equal "Goal 2 was the last you met, and it finished the story. You met goal 3 while Marek Sollen was " \
                 "still alive, which is what this ending is for.", Playthrough::EndNotice.for(@game).finished.reason
  end

  test "an ending reached late says by how much it was late" do
    @outcome = create(:quest_outcome, :slower_than, quest: @quest, name: "too-late", minutes: 150)
    met!(1, 2, 3)
    conclude!

    assert_match(/more than 2 hours and 30 minutes after the story began/, Playthrough::EndNotice.for(@game).finished.reason)
  end

  test "a game that did not conclude has nothing finished to say" do
    met!(1, 2, 3)
    kill!

    assert_nil Playthrough::EndNotice.for(@game).finished
  end

  def met!(*positions)
    summaries = [ "Climb to the bell.", "Get the tally.", "Take the bearing book." ]
    steps = summaries.each_with_index.map do |summary, index|
      create(:quest_step, :reach_location, quest: @quest, position: index + 1, summary: summary)
    end
    positions.each_with_index do |position, index|
      create(:playthrough_beat, playthrough: @game, quest_step: steps[position - 1],
                                reached_at: @story.start_time + (index * 10).minutes)
    end
    @quest.reload
  end

  def conclude!
    scene = create(:scene, story: @story, location: @room, previous_scene: @game.current_scene,
                           description: @outcome.summary, summary: @outcome.summary,
                           resolved_action: "conclude")
    create(:playthrough_ending, playthrough: @game, quest_outcome: @outcome)
    @game.update!(current_scene: scene)
    @game.end!
  end

  # The protagonist's condition row is stamped when the playthrough is created
  # (`Playthrough::Vitals`), so a death is that row taken to zero and not a
  # second one.
  def kill!
    Playthrough::Turn.new(@game).harm!(@vance, @vance.max_hp)
  end
end
