require "test_helper"

# THE BASELINE THAT SURVIVES A CLEAN CLONE.
#
# `tmp/eval` is a working directory: it gets cleaned, it is gitignored, and on a
# fresh clone it does not exist. So the set `ta-take-drop-narration` will be
# judged against is checked in under `db/eval`, and this is the test that it is
# still readable and still says what EVALUATION.md and the PR body say.
#
# NO DATABASE, NO KEY, NO NETWORK, and that is the point rather than a
# convenience: it is what makes today's numbers judgeable by somebody who has
# never paid for a call. The one exception is the cost row, which reads the
# `models` registry and degrades to `unpriced` rather than failing.
class Eval::Prompt::KeptSetTest < ActiveSupport::TestCase
  BASELINE = "prompt-2026-09-05".freeze

  ARM = "mistralai/mistral-medium-3.1".freeze

  test "the checked-in baseline loads off disk with its provenance in the file" do
    result = kept

    assert_equal BASELINE, result.name
    assert_equal [ ARM ], result.arms, "a set that does not say which model produced it is not a set"
    assert_equal [ ARM ], result.answered_by, "answered_by is the check on arms, and the pinning has to have held"
    assert_equal 4, result.reps, "four is Eval::Noise::MIN_RUNS -- fewer cannot be given a verdict"
    assert_equal Eval::Prompt.corpus.size, result.corpus_size
    assert_match(/\A2026-09-0/, result.recorded_at.to_s, "the date belongs in the file, not the filename")
    assert result.prompt_stable, "one case sending two prompts would make every figure in it suspect"
  end

  # THE DIGESTS ARE THE WHOLE POINT OF A KEPT SET. A later run is comparable
  # with this one only if both are known, and the corpus digest is what says the
  # cases did not move underneath the comparison.
  test "the baseline records the corpus and prompt it measured, and they are today's" do
    result = kept

    assert_equal Eval::Prompt.digest, result.corpus_digest,
                 "the corpus moved since the baseline was taken -- re-run it or the comparison is between two files"
    assert_equal Playthrough::PromptVersion.narration, result.instruction_passes["narration"],
                 "the narrator's instructions moved since the baseline was taken, so this is a baseline " \
                 "for a prompt the app no longer sends -- re-run it"
    assert_predicate result.instruction_passes["arrival"], :present?
    assert_predicate result.prompt_digest, :present?
  end

  # THE DEFECT THIS BENCH WAS BUILT FOR, on the record. `ta-take-drop-narration`
  # is judged against exactly this number, so a change to it that is not a
  # deliberate re-baseline is a failing test.
  test "the baseline reproduces the take/drop defect the bench was built for" do
    spread = kept.spread(:take_denied, arm: ARM)

    assert_operator spread.median, :>, 0.5,
                    "the narration denied the pickup on most takes -- that is what this baseline is for"
    assert_equal 18, kept.passes.first.judgeable["take_denied"], "18 take cases, and every one judgeable"
    assert_equal 18, kept.passes.first.judgeable["pickup_invented"]
  end

  # A KEPT SET IS A SUMMARY: the rows are dropped so it can live in the repo,
  # and everything the board and the comparison read has to survive that.
  test "the baseline is a summary and still renders a board with no rows" do
    result = kept

    assert_empty result.rows, "a kept set holds no readings, on purpose"
    board = Eval::Prompt::Board.new([ [ BASELINE, result ] ]).lines.join("\n")

    assert_includes board, "`#{ARM}`"
    assert_includes board, "`take_denied`"
    assert_includes board, "unavailable", "the four checks a single turn cannot answer stay unavailable"
    refute_includes board, "not recorded", "every figure the board prints was recorded"
  end

  test "the baseline is small enough to belong in a repository" do
    file = Eval.kept_root.join(BASELINE, Eval::Prompt::RESULTS)

    assert_operator File.size(file), :<, 100_000, "a kept set is figures, not passages"
  end

  # `Eval.set_path` IS THE ONE PLACE THE LOOKUP ORDER LIVES: a run somebody just
  # paid for wins over one the repo ships under the same name. Asserted against
  # two empty directories rather than against the real ones, for the reason
  # `Eval::Classifier::KeptSetsTest` gives: resolved by name, the baseline reads
  # `tmp/eval` on the machine that just ran the bench and `db/eval` in CI, and
  # would pass for two different reasons.
  test "a kept set is found when nothing local has that name, and a local run wins when one does" do
    Dir.mktmpdir do |root|
      local = Pathname.new(root).join("tmp")
      kept_root = Pathname.new(root).join("db")
      FileUtils.mkdir_p(local.join("both"))
      FileUtils.mkdir_p(kept_root.join("both"))
      FileUtils.mkdir_p(kept_root.join("kept-only"))

      Eval.stub(:root, local) do
        Eval.stub(:kept_root, kept_root) do
          assert_equal local.join("both").to_s, Eval.set_path("both").to_s
          assert_equal kept_root.join("kept-only").to_s, Eval.set_path("kept-only").to_s
        end
      end
    end
  end

  test "the manifest names the baseline, so deleting it is a failing test" do
    assert_includes Eval::MEASUREMENT_FILES, "db/eval/#{BASELINE}/#{Eval::Prompt::RESULTS}"
  end

  private

  def kept = @kept ||= Eval::Prompt::Result.load(Eval.kept_root.join(BASELINE))
end
