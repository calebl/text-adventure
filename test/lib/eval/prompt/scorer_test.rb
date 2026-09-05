require "test_helper"

# THE CHECKS, OVER STORED PASSAGES AND STORED FACTS.
#
# Nothing here is a new reading of prose: every predicate is
# `Story::Audit::Prose`'s, and what this class adds is the FACTS a single turn
# can supply in place of a live story. So the tests below are about the seam --
# which checks a case can answer, what their denominators are, and the four that
# must read UNAVAILABLE rather than clean.
#
# Offline, no records, no key, no network: the rows are the ones a set holds.
class Eval::Prompt::ScorerTest < ActiveSupport::TestCase
  FACTS = {
    "room" => "Ward Office 12",
    "from" => "Ward Office 12",
    "moved" => false,
    "protagonist" => [ "Odile Vance", "Vance", "Odile" ],
    "places" => { "ward office 12" => "Ward Office 12", "closet" => "The Supply Closet" },
    "exits" => [ "The Supply Closet" ],
    "present" => [ "Halkett Rowe" ],
    "floor" => [],
    "carried" => [ "ward stamp" ],
    "elsewhere" => [ { "name" => "copy-room apron", "whereabouts" => "lying in The Supply Closet", "here" => false } ],
    "action" => "take",
    "item" => "ward stamp",
    "inscription" => nil
  }.freeze

  # --- the two checks this bench was built for ------------------------------

  test "prose that says the player already had what the turn picked up is take_denied" do
    scorer = scored("You already hold the ward stamp, its weight familiar in your palm.")

    assert_equal [ :take_denied ], scorer.flags.map(&:code)
    assert_equal 1, scorer.judgeable_for(:take_denied)
    assert_in_delta 1.0, scorer.rate(:take_denied)
  end

  test "prose that describes the pickup it was told about is clean" do
    scorer = scored("You lift the ward stamp from the desk and close your hand around it.")

    assert_empty scorer.flags
    assert_in_delta 0.0, scorer.rate(:take_denied)
  end

  test "prose that lifts off a floor what the turn put down is pickup_invented" do
    scorer = scored("You pick the ward stamp up from the flagstones and set it on the bench.",
                    facts: FACTS.merge("action" => "drop"), act: "drop")

    assert_equal [ :pickup_invented ], scorer.flags.map(&:code)
    assert_equal 0, scorer.judgeable_for(:take_denied), "a drop is not a take, and its denominator says so"
    assert_equal 1, scorer.judgeable_for(:pickup_invented)
  end

  # --- the checks a case's facts make judgeable -----------------------------

  test "prose that hands the player something the records put elsewhere is item_not_held" do
    scorer = scored("You draw the copy-room apron from your satchel and shake it out.")

    assert_includes scorer.flags.map(&:code), :item_not_held
    assert_equal 1, scorer.judgeable_for(:item_not_held)
  end

  test "prose that writes the player as somebody else is third_person_protagonist" do
    scorer = scored("Odile Vance turns the stamp over in her hands and frowns at the ink.")

    assert_includes scorer.flags.map(&:code), :third_person_protagonist
  end

  test "prose that closes a door behind a player who did not move is unrecorded_departure" do
    scorer = scored("You step out and the door clicks shut behind you.")

    assert_includes scorer.flags.map(&:code), :unrecorded_departure
  end

  test "a case that MOVED is not judged for a departure it really made" do
    scorer = scored("You step out and the door clicks shut behind you.",
                    facts: FACTS.merge("moved" => true, "room" => "The Supply Closet"))

    refute_includes scorer.flags.map(&:code), :unrecorded_departure
  end

  test "prose that walks the player into another room is unrecorded_arrival" do
    scorer = scored("You step into the closet, and the office light stops at your shoulders.")

    assert_includes scorer.flags.map(&:code), :unrecorded_arrival
  end

  test "prose that stops mid-sentence is truncated_prose" do
    scorer = scored("You turn the stamp over and the ink on the pad is still")

    assert_includes scorer.flags.map(&:code), :truncated_prose
  end

  test "prose that quotes a record's words differently is inscription_misquoted" do
    scorer = scored(%(The page reads, in your own hand: "Nothing was entered after four."),
                    facts: FACTS.merge("item" => "Ward Office 12 daybook",
                                       "inscription" => "3.40 - Levee boundary. 4.00 -"))

    assert_includes scorer.flags.map(&:code), :inscription_misquoted
    assert_equal 1, scorer.judgeable_for(:inscription_misquoted)
  end

  test "a case with no words on record cannot be judged for misquoting them" do
    assert_equal 0, scored("anything at all").judgeable_for(:inscription_misquoted)
  end

  # --- what a single turn cannot answer -------------------------------------
  #
  # THE MOST DANGEROUS NUMBER THIS INSTRUMENT COULD PRINT is a clean rate for a
  # check it never ran. Each of these has a reason on
  # `Eval::Prompt::UNAVAILABLE_TO_A_CASE` and none of them is scored.
  test "the four checks a single turn cannot answer are not available at all" do
    scorer = scored("You wait.")

    %i[unreachable_transition reached_for_nothing named_more_than_one still_run].each do |code|
      refute_includes scorer.available_checks, code, "#{code} cannot be answered by one turn"
      assert_equal 0, scorer.judgeable_for(code)
      assert Eval::Prompt::UNAVAILABLE_TO_A_CASE.key?(code), "and it has to say why"
    end
  end

  test "every check the scoreboard has is either scored or named unavailable" do
    assert_equal Story::Scoreboard::CHECKS.keys.sort,
                 (Eval::Prompt.checks + Eval::Prompt::UNAVAILABLE_TO_A_CASE.keys).sort,
                 "a check that is neither would be silently dropped"
  end

  # --- richness, which is never folded in -----------------------------------

  test "richness counts what the prose committed to and is not a rate" do
    scorer = scored("You take the ward stamp from the desk. Halkett Rowe watches from the doorway.")

    assert_operator scorer.richness.commitments, :>, 0
    assert_operator scorer.richness.words, :>, 0
  end

  # A FAILED CALL IS NOT A CLEAN PASSAGE, which is the one way this could report
  # a refusal as a good turn.
  test "a row that failed is not scored at all" do
    scorer = Eval::Prompt::Scorer.new([ row(nil).merge("error" => "BaseAgent::RefusalError: no") ])

    assert_equal 0, scorer.scanned
    assert_empty scorer.flags
    assert_equal 0, scorer.judgeable_for(:take_denied)
  end

  private

  def scored(text, facts: FACTS, act: "take")
    Eval::Prompt::Scorer.new([ row(text, facts: facts, act: act) ])
  end

  def row(text, facts: FACTS, act: "take")
    { "id" => "a-case", "shape" => act, "act" => act, "story" => "The Unrecorded Hour",
      "arm" => "fake/model", "rep" => 1, "typed" => "pick up the ward stamp",
      "text" => text, "facts" => facts, "error" => nil }
  end
end
