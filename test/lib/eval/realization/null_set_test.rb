require "test_helper"

# THE NOISE BAND, AS A CHECKED-IN PAIR OF FILES.
#
# WHAT THIS SET IS. `db/eval/null-2026-09-07` is the realization bench run
# against the SAME prompt the baseline beside it measured -- same corpus, same
# model, same digest, four repetitions -- so the only thing that differs between
# the two is the run. Everything it moves is the bench disagreeing with itself.
#
# WHY IT EXISTS AT ALL, AND IT IS WORTH SAYING PLAINLY: it was bought by
# mistake. `rake eval:realization` has no estimate-only mode and spends the
# moment it is called; the round was started expecting a price and produced a
# measurement. What was paid for is kept here rather than deleted, because a
# null check is the one run the protocol asks for that nobody ever wants to
# fund: `EVALUATION.md` opens by saying two identical runs disagree by more than
# most claimed improvements, and until this file that spread was an argument
# rather than a table anybody could read.
#
# WHAT IT IS FOR. Before believing a REAL verdict on some figure, read what the
# same prompt twice already did to that figure. `race_not_named` moves from
# 0.500 to 1.000 across two runs of one prompt -- so a swing of that size in a
# before/after is not evidence of anything, and this file is where a reader
# finds that out for free.
#
# IT PINS NO NUMBER. The figures live in the files and are read with
# `rake eval:realization_compare BEFORE=room-people-after AFTER=null-2026-09-07`,
# for `Eval::Realization::KeptSetTest`'s reason. What is asserted here is the
# only claim the pair makes: the prompt did not move, and neither did anything
# else past what the run itself spans.
class Eval::Realization::NullSetTest < ActiveSupport::TestCase
  NULL_SET = "null-2026-09-07".freeze

  # NAMED, NOT `BASELINE`. The pair is two stored files and the claim is about
  # those two, so re-pointing `Eval::Realization::BASELINE` at some later after
  # side must not make this test fail -- the band this pair measured stays a
  # true thing about the digest it was taken at. `Eval::Realization::KeptSetTest`
  # owns the other claim, that the baseline is the prompt this tree sends.
  PAIRED_WITH = "room-people-after".freeze

  ARM = "mistralai/mistral-medium-3.1".freeze

  test "the null set loads off disk with its provenance in the file" do
    assert_equal NULL_SET, null.name
    assert_equal [ ARM ], null.arms
    assert_equal [ ARM ], null.answered_by, "a set nothing answered measures nothing"
    assert_equal Eval::Noise::MIN_RUNS, null.reps, "fewer repetitions than the floor cannot be given a verdict"
    assert null.prompt_stable, "one case sending two prompts would make this a band for two prompts"
    assert_empty null.rows, "a kept set holds no readings, on purpose"
  end

  # THE DEFINITION OF A NULL CHECK, and the thing that would quietly stop being
  # true if either file were edited: one prompt, one model, one corpus, two runs.
  test "the pair measured one prompt twice" do
    assert_equal paired.prompt_digest, null.prompt_digest,
                 "the two sets record different prompts, so what separates them is not the bench disagreeing " \
                 "with itself and this is not a noise band"
    assert comparison.comparable_corpus?, "two sets that built different rooms are not a null check"
    assert_not comparison.cross_model?, "two models are two measurements, not one measured twice"
    assert_not comparison.cross_prompt?
  end

  # THE VERDICT, ASSERTED. Nothing the same prompt did twice may read REAL --
  # that is what `Eval::Noise` promises and this is the pair that can hold it to
  # it. INCONCLUSIVE is a failure here too: at the repetition floor, on a pair
  # that differs in nothing, the test has to be able to say NOISE.
  test "no figure separates the run from itself" do
    separated = comparison.verdicts(ARM).reject { |row| row.verdict.noise? }

    assert_empty separated.map { |row| "#{row.metric} #{row.verdict.headline}" },
                 "the same prompt measured twice separated on a figure -- either the band is being read as " \
                 "an improvement somewhere, or Eval::Noise has moved"
  end

  test "the comparison says in words that this is the null check" do
    printed = StringIO.new
    Eval::Realization::Comparison.new(paired, null, io: printed).print

    assert_includes printed.string, "the null check"
    assert_includes printed.string, "Everything below should read NOISE."
  end

  test "the null set is small enough to belong in a repository" do
    file = Eval.kept_root.join(NULL_SET, Eval::Realization::RESULTS)

    assert_operator File.size(file), :<, 100_000, "a kept set is figures, not rooms"
  end

  test "the manifest names the null set, so deleting it is a failing test" do
    assert_includes Eval::MEASUREMENT_FILES, "db/eval/#{NULL_SET}/#{Eval::Realization::RESULTS}"
  end

  private

  def null = @null ||= Eval::Realization::Result.load(Eval.kept_root.join(NULL_SET))

  def paired = @paired ||= Eval::Realization::Result.load(Eval.kept_root.join(PAIRED_WITH))

  def comparison = @comparison ||= Eval::Realization::Comparison.new(paired, null, io: nil)
end
