require "test_helper"

# THE SET: WRITTEN, READ BACK, AND STILL THE SAME MEASUREMENT.
#
# A bench run is only worth what its file is worth. Two things have to hold and
# both are easy to lose:
#
#   * A SET READ OFF DISK ANSWERS EXACTLY WHAT THE LIVE RUN ANSWERED. One code
#     path computes a figure (`Result.figures_of`) and both sides use it, so a
#     board printed from a file and a board printed from a run are the same
#     board.
#   * A KEPT SET IS A SUMMARY AND STILL RENDERS. The rows are dropped so the
#     file can be checked in, and everything the board and the comparison read
#     has to survive that -- which is only true because the figures were
#     computed before the rows went.
class Eval::Prompt::ResultTest < ActiveSupport::TestCase
  ROWS = [
    { "id" => "a-take", "shape" => "take", "act" => "take", "story" => "The Unrecorded Hour",
      "arm" => "fake/model", "rep" => 1, "typed" => "pick up the ward stamp",
      "text" => "You already hold the ward stamp.", "seconds" => 1.5,
      "input_tokens" => 800, "output_tokens" => 120, "calls" => 1, "answered_by" => "fake/model",
      "missing_fields" => [], "cap_hits" => [], "error" => nil,
      "facts" => { "room" => "Ward Office 12", "moved" => false, "action" => "take",
                   "item" => "ward stamp", "protagonist" => [ "Odile Vance" ], "places" => {},
                   "exits" => [], "present" => [], "floor" => [], "carried" => [ "ward stamp" ],
                   "elsewhere" => [], "inscription" => nil } },
    { "id" => "a-drop", "shape" => "drop", "act" => "drop", "story" => "The Salt Assizes",
      "arm" => "fake/model", "rep" => 1, "typed" => "set the slate down",
      "text" => "You set the Assize tide-slate on the bench.", "seconds" => 2.5,
      "input_tokens" => 700, "output_tokens" => 100, "calls" => 1, "answered_by" => "fake/model",
      "missing_fields" => [], "cap_hits" => [ "summary" ], "error" => nil,
      "facts" => { "room" => "The Causeway Court", "moved" => false, "action" => "drop",
                   "item" => "Assize tide-slate", "protagonist" => [ "Coraith Vell" ], "places" => {},
                   "exits" => [], "present" => [], "floor" => [ "Assize tide-slate" ], "carried" => [],
                   "elsewhere" => [], "inscription" => nil } }
  ].freeze

  def setup
    @result = result_with(reps: 2)
  end

  test "a figure is computed one way, whether the pass is live or loaded" do
    round_tripped = written_and_loaded(@result)

    Eval::Prompt::Result.metrics.each_key do |metric|
      assert_equal @result.values(metric), round_tripped.values(metric),
                   "#{metric} came back different after a round trip"
    end
    assert_equal @result.corpus_digest, round_tripped.corpus_digest
    assert_equal @result.prompt_digest, round_tripped.prompt_digest
    assert_equal @result.arms, round_tripped.arms
  end

  test "the checks are rates and the operational figures are counts" do
    pass = @result.passes.first

    assert_in_delta 1.0, pass.figure(:take_denied), 0.001, "the take passage denies the pickup"
    assert_in_delta 0.0, pass.figure(:pickup_invented), 0.001, "\"set down\" is not a pickup verb"
    assert_equal 1, pass.figure(:cap_hits)
    assert_equal 0, pass.figure(:failures)
    assert_in_delta 2.0, pass.figure(:latency_median), 0.001
  end

  # A KEPT SET IS 8 KB AND RENDERS THE SAME TABLE, which is the whole reason a
  # baseline can be checked in at all.
  test "a summary keeps every figure and drops every row" do
    summary = @result.summary

    assert_empty summary.passes.flat_map(&:rows), "a kept set holds no readings, on purpose"
    Eval::Prompt::Result.metrics.each_key do |metric|
      assert_equal @result.values(metric), summary.values(metric), "#{metric} did not survive the summary"
    end
    assert_equal @result.answered_by, summary.answered_by,
                 "answered_by is provenance, and a summary has no rows to re-derive it from"
  end

  test "a summary written and read back still renders a board" do
    board = Eval::Prompt::Board.new([ [ "kept", written_and_loaded(@result.summary) ] ])

    assert_includes board.lines.join("\n"), "`take_denied`"
    assert_includes board.lines.join("\n"), "fake/model"
  end

  # THE DIRECTION OF IMPROVEMENT IS ASKED OF THE METRIC AND NOT OF THE VERDICT,
  # because `Eval::Noise` reads a negative delta as an improvement and that is
  # backwards for nothing here -- but richness has no better direction at all,
  # and saying so is the point of printing it.
  test "every metric is either lower-is-better or explicitly neutral" do
    Eval::Prompt::Result.metrics.each_key do |metric|
      assert Eval::Prompt::Result.lower_is_better.include?(metric) ||
             Eval::Prompt::Result::NEUTRAL.include?(metric),
             "#{metric} has no stated direction, so a comparison cannot say BETTER or WORSE"
    end
  end

  test "loading a set that does not exist says how to make one" do
    error = assert_raises(ArgumentError) { Eval::Prompt::Result.load(Dir.mktmpdir) }

    assert_match(/rake eval:prompt SET=/, error.message)
  end

  private

  def result_with(reps:)
    passes = (1..reps).map do |rep|
      rows = ROWS.map { |row| row.merge("rep" => rep) }
      Eval::Prompt::Result::Stored.new({ "arm" => "fake/model", "rep" => rep }
        .merge(Eval::Prompt::Result.figures_of(rows)).merge("readings" => rows))
    end

    Eval::Prompt::Result.new(corpus_size: 2, corpus_digest: "corpus0000000000",
                             prompt_digest: "prompt0000000000", instructions_digest: "instr00000000000",
                             prompt_shapes: { "take" => "aaaa", "drop" => "bbbb" },
                             arms: [ "fake/model" ], reps: reps, passes: passes,
                             warmups: [ { arm: "fake/model", seconds: 3.0, residency: "not_local", error: nil } ],
                             name: "a-set")
  end

  def written_and_loaded(result)
    directory = Pathname.new(Dir.mktmpdir)
    result.write!(directory, name: result.name)
    Eval::Prompt::Result.load(directory)
  end
end
