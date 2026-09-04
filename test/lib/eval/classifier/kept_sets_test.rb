require "test_helper"

# THE BASELINE THAT SURVIVES A CLEAN CLONE.
#
# THE CAPTAIN'S INSTRUCTION OF 2026-09-04: *"make the bench's results
# referenceable by tooling, not only by the prose table… so a future run can be
# compared against today's baseline on any machine with a real REAL/NOISE
# verdict."*
#
# `tmp/eval` is a working directory: it gets cleaned, it is gitignored, and on a
# fresh clone it does not exist. So the sets worth keeping are checked in under
# `db/eval`, and this is the test that they are still readable and still say
# what the prose table in EVALUATION.md says.
#
# NO DATABASE, NO KEY, NO NETWORK, and that is the point rather than a
# convenience: it is what makes today's numbers judgeable by somebody who has
# never paid for a call. Nothing here touches a model, a fixture or a row --
# `Eval::Classifier::Result.load` reads a file and `Board` formats it. The one
# exception is the cost row, which reads the `models` registry and is asserted
# to degrade to `unpriced` rather than to fail.
class Eval::Classifier::KeptSetsTest < ActiveSupport::TestCase
  # The sets EVALUATION.md's baseline table is built from. Named here so that
  # deleting one is a failing test rather than a table that quietly loses a
  # column.
  BASELINE = %w[classifier-remote classifier-mistral-small classifier-gemini-flash-lite].freeze

  # Every arm the baseline measured, and the figures the PR body and
  # EVALUATION.md quote for it. If a checked-in file is ever regenerated, this
  # is what says the prose and the files still agree.
  EXPECTED = {
    "mistralai/mistral-medium-3.1" => { set: "classifier-remote", strict: 0.947, misses: 9.5, failures: 0 },
    "minimax/minimax-m3" => { set: "classifier-remote", strict: 0.918, misses: 17, failures: 1.5 },
    "mistralai/mistral-small-3.2-24b-instruct" =>
      { set: "classifier-mistral-small", strict: 0.875, misses: 30.5, failures: 7 },
    "google/gemini-2.5-flash-lite" =>
      { set: "classifier-gemini-flash-lite", strict: 0.898, misses: 11, failures: 0 }
  }.freeze

  test "every checked-in set loads off disk with its provenance in the file" do
    BASELINE.each do |name|
      result = load_kept(name)

      assert_equal name, result.name
      assert_predicate result.arms, :any?, "a set that does not say which model produced it is not a set"
      assert_equal "33591b8ff9b42d87", result.corpus_digest,
                   "the digest is how a later run knows it was scored on the same labels"
      assert_equal 300, result.corpus_size
      assert_equal 4, result.reps, "four is Eval::Noise::MIN_RUNS -- fewer cannot be given a verdict"
      assert_match(/\A2026-09-04T/, result.recorded_at.to_s, "the date belongs in the file, not the filename")
      assert_equal result.arms.sort, result.answered_by.sort,
                   "answered_by is the check on arms, and a summary set has no rows to re-derive it from"
    end
  end

  test "the four arms carry the figures EVALUATION.md and the PR body quote" do
    EXPECTED.each do |arm, expected|
      result = load_kept(expected[:set])

      assert_includes result.arms, arm
      assert_equal 4, result.for_arm(arm).size, "four repetitions, or the band is not a band"
      assert_in_delta expected[:strict], result.spread(:strict_accuracy, arm: arm).median, 0.0005
      assert_in_delta expected[:misses], result.spread(:closed_set_misses, arm: arm).median, 0.001
      assert_in_delta expected[:failures], result.spread(:failures, arm: arm).median, 0.001
    end
  end

  # THE WHOLE POINT: the board renders, from files alone.
  test "the board renders the baseline table out of the checked-in files" do
    board = Eval::Classifier::Board.new(BASELINE.map { |name| [ name, load_kept(name) ] })
    printed = board.lines.join("\n")

    assert_equal EXPECTED.keys.size, board.columns.size, "one column an arm, not one a set"
    EXPECTED.each_key { |arm| assert_match(/#{Regexp.escape(arm)}/, printed) }
    assert_match(%r{`closed_set_misses` \| 8\.\.11 \(9\.5\)}, printed,
                 "the median of four counts keeps its half -- see Eval.count")
    assert_match(/omission rate \| 0\.000 \(0 of 1200\)/, printed,
                 "PR 102's finding F4, still answerable with no key and no calls")
    assert_match(/latency median \(warm\) \| 0\.60s\.\.0\.62s \(0\.61s\)/, printed)
    assert_empty board.warnings, "one corpus digest across the baseline, so nothing to warn about"
  end

  # A SUMMARY IS ENOUGH FOR THE TWO READERS AND NOTHING MORE, so what it gave up
  # is asserted rather than left to be discovered by a caller expecting rows.
  test "the kept sets are summaries: every figure, no per-line rows" do
    result = load_kept("classifier-remote")

    assert_empty result.rows, "1.1MB a model of readings is right for tmp/eval and wrong for the repo"
    result.passes.each do |pass|
      assert_equal 300, pass.also_counts[:readings_count],
                   "the counts have to survive the rows, or the table cannot be rebuilt"
      assert_not_nil pass.strict_accuracy
      assert_not_nil pass.latency_p95
    end
  end

  # AND IT IS SMALL, which is the constraint that made it a summary at all.
  test "the whole checked-in baseline is kilobytes, not megabytes" do
    bytes = BASELINE.sum { |name| File.size(Eval.kept_root.join(name, Eval::Classifier::RESULTS)) }

    assert_operator bytes, :<, 64.kilobytes,
                    "the runs these came from are 4.4MB together; a repo file has to be a summary"
  end

  # THE LOOKUP ORDER, which is the part a person could be surprised by: a set
  # you just paid for wins over one the repo ships under the same name.
  test "a local run wins over the checked-in set of the same name" do
    Dir.mktmpdir do |dir|
      local = Pathname.new(dir).join("tmp-eval")
      kept = Pathname.new(dir).join("db-eval")
      FileUtils.mkdir_p(local.join("both"))
      FileUtils.mkdir_p(kept.join("both"))
      FileUtils.mkdir_p(kept.join("kept-only"))

      Eval.stub(:root, local) do
        Eval.stub(:kept_root, kept) do
          assert_equal local.join("both").to_s, Eval.set_path("both").to_s
          assert_equal kept.join("kept-only").to_s, Eval.set_path("kept-only").to_s
          assert_equal local.join("neither").to_s, Eval.set_path("neither").to_s,
                       "a name in neither place resolves to tmp/eval, where a run would write it"
        end
      end
    end
  end

  private
    # Loaded from the KEPT root explicitly rather than through `Eval.set_path`,
    # because this test is about the checked-in files: resolved by name it would
    # read `tmp/eval` on the machine that just ran the bench and `db/eval` in
    # CI, and pass for two different reasons.
    def load_kept(name) = Eval::Classifier::Result.load(Eval.kept_root.join(name))
end
