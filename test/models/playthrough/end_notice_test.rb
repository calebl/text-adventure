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

  # NO THIRD SET OF WORDS. A game the records cannot explain shows the death
  # copy and is reported by `Story::Doctor`; see this class's header.
  test "an unrecorded ending shows the death copy" do
    @game.end!

    assert_equal Playthrough::DeathNotice::HEADING, Playthrough::EndNotice.for(@game).heading
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
