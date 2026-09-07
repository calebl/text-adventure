require "test_helper"

# THE REALIZATION BASELINE THAT SURVIVES A CLEAN CLONE.
#
# `tmp/eval` is a working directory: it gets cleaned, it is gitignored, and on a
# fresh clone it does not exist. So the set the room naming block was
# re-baselined on is checked in under `db/eval`, and this is the test that it is
# still readable and still says what EVALUATION.md and the PR body say about it.
# `Eval::Prompt::KeptSetTest`'s argument, applied to the room builder's bench.
#
# NO KEY AND NO NETWORK, which is the point rather than a convenience: it is
# what makes the figures judgeable by somebody who has never paid for a call.
# The cost row is the one exception and degrades to `unpriced` rather than
# failing, because it reads the `models` registry.
#
# IT ASSERTS NO RATE, deliberately, and that is the difference between this and
# the prompt bench's kept-set test. That one pins the take/drop defect the bench
# was built for, because the whole point of that baseline is a number a later
# change is judged against. This bench's checked-in set is the AFTER side of a
# judged change: the numbers live in the file and are read with
# `rake eval:realization_board`, and a number copied into an assertion here
# would be a second place they were written down.
class Eval::Realization::KeptSetTest < ActiveSupport::TestCase
  # NAMED ONCE, IN THE APP, and read here. `Eval::Realization::BASELINE` is what
  # `rake eval:realization_digest` compares this tree against, so a second
  # spelling of the name would be a second answer to "what is the baseline".
  BASELINE = Eval::Realization::BASELINE

  ARM = "mistralai/mistral-medium-3.1".freeze

  test "the checked-in baseline loads off disk with its provenance in the file" do
    result = kept

    assert_equal BASELINE, result.name
    assert_equal [ ARM ], result.arms, "a set that does not say which model produced it is not a set"
    assert_equal [ ARM ], result.answered_by, "answered_by is the check on arms, and the pinning has to have held"
    assert_equal Eval::Noise::MIN_RUNS, result.reps, "fewer repetitions than the floor cannot be given a verdict"
    assert_match(/\A2026-09-0/, result.recorded_at.to_s, "the date belongs in the file, not the filename")
    assert result.prompt_stable, "one case sending two prompts would make every figure in it suspect"
    assert_predicate result.prompt_digest, :present?
    assert_predicate result.instructions_digest, :present?
  end

  # THE CORPUS DIGEST IS WHAT MAKES A LATER RUN COMPARABLE WITH THIS ONE: it is
  # the claim that the cases did not move underneath the comparison. A corpus
  # that has moved makes `rake eval:realization_compare` a comparison between
  # two files rather than between two prompts.
  test "the baseline records the corpus it measured, and it is today's" do
    assert_equal Eval::Realization.digest, kept.corpus_digest,
                 "the corpus moved since the baseline was taken -- re-run it, or the comparison means nothing"
    assert_equal Eval::Realization.corpus.size, kept.corpus_size
  end

  # AND THE PROMPTS IT MEASURED ARE THE PROMPTS IN THIS TREE, which is the
  # corpus digest's argument said about the other half of what a run measures --
  # and the half that had no offline check at all until
  # `Eval::Realization::Version.offline`. The captain's standing rule of
  # 2026-09-06 is that a prompt change is judged against a baseline; this is the
  # assertion that makes shipping one without a baseline a failing test rather
  # than a thing nobody could see. A prompt edit re-baselines and moves
  # `Eval::Realization::BASELINE`, in that order.
  #
  # IT ASSEMBLES THE PROMPTS RATHER THAN READING THEM OFF THE SET, so what is
  # compared is what `Location::Generator` would send TODAY. No key, no network,
  # no spend.
  test "the baseline measured the prompts this tree would send" do
    assert_equal Eval::Realization::Version.offline[:prompt_digest], kept.prompt_digest,
                 "the realization prompts moved since the baseline was taken -- buy an after side and " \
                 "point Eval::Realization::BASELINE at it, or put the prompt back"
  end

  # THE NAMING ASK WAS IN THE PROMPT WHEN THIS WAS TAKEN, which is the one fact
  # about this set that makes it the AFTER side rather than a run beside it:
  # both name checks earned a denominator. Read off `name_asked`, the fact the
  # bench stores per row -- a set recorded before `Location::DetailSchema`
  # carried a `name` reports both checks `unavailable`, and that is what the
  # before side of this pair does.
  #
  # EACH CHECK AGAINST ITS OWN PREDICATE, AND THE TWO ARE NOT THE SAME ONE.
  # `Eval::Realization::Scorer#judge_room_name_refused` judges a room the prompt
  # asked whose name is on record afterwards -- which is every room it asked,
  # since a room always has a name. `#judge_room_name_already_taken` judges a
  # room the prompt asked THAT PROPOSED SOMETHING, and `name` is an optional
  # field, so a room that came back without one is in the first denominator and
  # not the second. The two figures are equal in this set because this arm
  # answered every time; that is a fact about the run and not a rule, so it is
  # not what is asserted here.
  test "the baseline was taken with the naming ask in the prompt" do
    judgeable = kept.passes.map { |pass| pass.judgeable.slice("room_name_refused", "room_name_already_taken") }

    judgeable.each do |pass|
      assert_operator pass["room_name_refused"].to_i, :>, 0,
                      "no room in this set was asked to name itself, so it is not a baseline for the naming block"
      assert_operator pass["room_name_already_taken"].to_i, :>, 0,
                      "no room the prompt asked proposed a name, so the collision check earned no rate"
    end
  end

  # A KEPT SET IS A SUMMARY: the rows are dropped so it can live in the repo,
  # and everything the board and the comparison read has to survive that.
  test "the baseline is a summary and still renders a board with no rows" do
    result = kept

    assert_empty result.rows, "a kept set holds no readings, on purpose"
    table = Eval::Realization::Board.new([ [ BASELINE, result ] ]).lines.join("\n")

    assert_includes table, "`#{ARM}`"
    assert_includes table, "`room_name_refused`"
    assert_not_includes table, "not recorded", "every figure the board prints was recorded"
  end

  test "the baseline is small enough to belong in a repository" do
    file = Eval.kept_root.join(BASELINE, Eval::Realization::RESULTS)

    assert_operator File.size(file), :<, 100_000, "a kept set is figures, not rooms"
  end

  test "the manifest names the baseline, so deleting it is a failing test" do
    assert_includes Eval::MEASUREMENT_FILES, "db/eval/#{BASELINE}/#{Eval::Realization::RESULTS}"
  end

  private

  def kept = @kept ||= Eval::Realization::Result.load(Eval.kept_root.join(BASELINE))
end
