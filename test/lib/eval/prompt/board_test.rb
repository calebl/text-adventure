require "test_helper"

# EVERY SET ON DISK AS ONE TABLE, AND THE CHECK ON THE SET CONVENTION.
#
# The board reads `<set>/prompt.json` and NOTHING else -- no database, no key,
# no model, no corpus -- so if a set cannot answer for itself here, it did not
# record enough. That is what these tests are for; the arithmetic is
# `Eval::Prompt::Result`'s and is tested there.
class Eval::Prompt::BoardTest < ActiveSupport::TestCase
  test "a set renders with one column per arm and a row per check" do
    table = board(set("one")).lines.join("\n")

    Eval::Prompt.checks.each { |code| assert_includes table, "`#{code}`" }
    assert_includes table, "prompt version"
    assert_includes table, "cost per 1,000 narrations"
  end

  # A CHECK THE CORPUS CANNOT JUDGE READS `unavailable` AND NEVER `0.000`, which
  # is the rule the whole of this module works to.
  test "a check with nothing judgeable reads unavailable and not zero" do
    table = board(set("one", judgeable: 0)).lines.join("\n")

    assert_includes table, "unavailable"
    refute_includes table, "0.000 (0..0 of 0)"
  end

  # TWO SETS ON DIFFERENT CORPORA ARE NOT COMPARABLE, and a table is the easiest
  # place in the world to forget it.
  test "sets scored on different corpora are called out under the table" do
    warnings = board(set("one", corpus: "aaaa"), set("two", corpus: "zzzz")).warnings.join("\n")

    assert_includes warnings, "did not score the same cases"
  end

  test "a set whose prompt was not stable is called out under the table" do
    warnings = board(set("one", stable: false)).warnings.join("\n")

    assert_includes warnings, "UNSTABLE prompt"
  end

  # TWO PROMPT VERSIONS SIDE BY SIDE IS THE POINT AND NOT A WARNING: it is what
  # a before/after looks like on one board.
  test "two prompt versions are tabulated without complaint" do
    board = board(set("one", prompt: "aaaa"), set("two", prompt: "bbbb"))

    assert_empty board.warnings
    assert_includes board.lines.join("\n"), "`aaaa`"
    assert_includes board.lines.join("\n"), "`bbbb`"
  end

  test "no sets at all says how to make one" do
    Eval.stub(:root, Pathname.new(Dir.mktmpdir)) do
      Eval.stub(:kept_root, Pathname.new(Dir.mktmpdir)) do
        error = assert_raises(ArgumentError) { Eval::Prompt::Board.for_sets([]) }

        assert_match(/run `rake eval:prompt` first/, error.message)
      end
    end
  end

  private

  def board(*results) = Eval::Prompt::Board.new(results.map { |result| [ result.name, result ] })

  def set(name, prompt: "aaaa", corpus: "cccc", judgeable: 10, stable: true)
    passes = (1..4).map do |rep|
      Eval::Prompt::Result::Stored.new(
        "arm" => "fake/model", "rep" => rep, "readings" => [],
        "rates" => Eval::Prompt.checks.index_with { |_code| 0.1 }.transform_keys(&:to_s),
        "flagged" => Eval::Prompt.checks.index_with { |_code| 1 }.transform_keys(&:to_s),
        "judgeable" => Eval::Prompt.checks.index_with { |_code| judgeable }.transform_keys(&:to_s),
        "scanned" => 10, "cases" => 10, "failures" => 0, "refusals" => 0, "rotations" => 0,
        "omitted_fields" => 0, "cap_hits" => 0, "input_tokens" => 100, "output_tokens" => 100,
        "latency_median" => 1.0, "latency_p95" => 2.0, "words" => 90, "commitments" => 3.0
      )
    end

    Eval::Prompt::Result.new(name: name, corpus_size: 10, corpus_digest: corpus,
                             prompt_digest: prompt, prompt_stable: stable,
                             instructions_digest: prompt, arms: [ "fake/model" ], reps: 4,
                             passes: passes,
                             warmups: [ { arm: "fake/model", seconds: 2.0, residency: "not_local", error: nil } ])
  end
end
