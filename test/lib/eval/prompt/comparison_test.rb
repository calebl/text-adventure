require "test_helper"

# TWO SETS, AND WHAT MAY BE CONCLUDED FROM THE PAIR.
#
# The verdict itself is `Eval::Noise`'s and is tested there. What is tested here
# is the thing that decides whether a verdict MEANS anything: which of the two
# things -- the model or the prompt -- actually changed. A set records both
# digests so that question can be answered off the files alone, and the printer
# has to say the answer out loud, because a table of verdicts is the easiest
# place in the world to forget it.
class Eval::Prompt::ComparisonTest < ActiveSupport::TestCase
  test "one model, two prompt versions: the ordinary before/after" do
    comparison = compare(set("before", prompt: "aaaa"), set("after", prompt: "bbbb"))

    assert comparison.cross_prompt?
    refute comparison.cross_model?
    assert_includes printed(comparison), "This is a PROMPT comparison on one model: aaaa -> bbbb."
  end

  test "one prompt version, two models: the model comparison" do
    comparison = compare(set("before", prompt: "aaaa", arm: "one/model"),
                         set("after", prompt: "aaaa", arm: "two/model"))

    assert comparison.cross_model?
    refute comparison.cross_prompt?
    assert_includes printed(comparison), "THIS IS A MODEL COMPARISON on one prompt version"
  end

  # THE PAIR NOTHING CAN BE CONCLUDED FROM, and the one this exists to catch.
  test "both changed at once is refused to be read, loudly" do
    comparison = compare(set("before", prompt: "aaaa", arm: "one/model"),
                         set("after", prompt: "bbbb", arm: "two/model"))

    assert_includes printed(comparison), "THE MODEL AND THE PROMPT BOTH CHANGED"
  end

  test "the same prompt twice is the null check and says so" do
    comparison = compare(set("before", prompt: "aaaa"), set("after", prompt: "aaaa"))

    assert_includes printed(comparison), "Everything below should read NOISE"
  end

  # TWO SETS SCORED ON DIFFERENT CASES ARE NOT COMPARABLE AT ALL, which is worse
  # than either of the above and gets the same treatment as the classifier
  # bench's corpus mismatch.
  test "a different corpus is a warning above the verdicts" do
    comparison = compare(set("before", corpus: "aaaa"), set("after", corpus: "zzzz"))

    refute comparison.comparable_corpus?
    assert_includes printed(comparison), "THE TWO SETS SCORED DIFFERENT CORPORA"
  end

  test "nothing in common and several models a side names the pair rather than guessing" do
    before = set("before", arm: "one/model")
    before.arms << "two/model"

    error = assert_raises(Eval::Prompt::Comparison::Unpairable) do
      compare(before, set("after", arm: "three/model")).pairs
    end

    assert_match(/BEFORE_MODEL=/, error.message)
  end

  # RICHNESS IS PRINTED WITH NO ARROW ON IT. A fall in every defect rate beside
  # a fall in `commitments` is prose that says less, which is the one way to
  # improve these numbers without improving the game.
  test "a neutral figure is reported and never called better or worse" do
    comparison = compare(set("before", prompt: "aaaa"), set("after", prompt: "bbbb"))
    row = comparison.verdicts("fake/model").find { |found| found.metric == :commitments }

    assert row.neutral?
    assert_equal "reported", row.direction
  end

  private

  def compare(before, after) = Eval::Prompt::Comparison.new(before, after, io: nil)

  def printed(comparison)
    buffer = StringIO.new
    Eval::Prompt::Comparison.new(comparison.before, comparison.after, io: buffer).print
    buffer.string
  end

  def set(name, prompt: "aaaa", corpus: "cccc", arm: "fake/model")
    passes = (1..4).map do |rep|
      Eval::Prompt::Result::Stored.new(
        "arm" => arm, "rep" => rep, "readings" => [],
        "rates" => Eval::Prompt.checks.index_with { |_code| 0.1 }.transform_keys(&:to_s),
        "flagged" => Eval::Prompt.checks.index_with { |_code| 1 }.transform_keys(&:to_s),
        "judgeable" => Eval::Prompt.checks.index_with { |_code| 10 }.transform_keys(&:to_s),
        "scanned" => 10, "cases" => 10, "failures" => 0, "refusals" => 0, "crises" => 0,
        "rotations" => 0, "extra_calls" => 0, "omitted_fields" => 0, "cap_hits" => 0,
        "input_tokens" => 100, "output_tokens" => 100, "latency_median" => 1.0,
        "latency_p95" => 2.0, "words" => 90, "commitments" => 3.0, "coverage" => 0.5, "chars" => 500
      )
    end

    Eval::Prompt::Result.new(name: name, corpus_size: 10, corpus_digest: corpus,
                             prompt_digest: prompt, instructions_digest: prompt,
                             arms: [ arm ], reps: 4, passes: passes)
  end
end
