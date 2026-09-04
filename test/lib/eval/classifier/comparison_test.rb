require "test_helper"

# JUDGING A PROMPT CHANGE, which is what the whole bench is for -- and the
# failure this guards is a verdict of REAL on two runs that differ only in what
# a provider sampled. That is the same hazard `Eval::NoiseTest` is written
# against, and the rule is the same module, so what is tested here is only the
# part this class adds: the DIRECTION.
#
# THE DIRECTION IS NOT OBVIOUS AND IS EASY TO GET BACKWARDS. `Eval::Noise` was
# built for defect counts, where a fall is an improvement. Four of the five
# figures on this board are accuracies, where a fall is a regression, and
# `closed_set_misses` is a count where it is not. Reading "BETTER" off a
# verdict's own `#improved?` would have got four of five wrong.
class Eval::Classifier::ComparisonTest < ActiveSupport::TestCase
  test "an accuracy that rose reads as better and one that fell reads as worse" do
    rows = compare(strict_accuracy: [ [ 0.80, 0.81, 0.79, 0.80 ], [ 0.90, 0.91, 0.92, 0.90 ] ])

    row = rows.find { |candidate| candidate.metric == :strict_accuracy }
    assert row.improved?, "0.80 -> 0.90 on an accuracy is an improvement"
    assert_equal "BETTER", row.direction

    fell = compare(strict_accuracy: [ [ 0.90, 0.91, 0.92, 0.90 ], [ 0.80, 0.81, 0.79, 0.80 ] ])
                   .find { |candidate| candidate.metric == :strict_accuracy }
    assert_not fell.improved?
    assert_equal "WORSE", fell.direction
  end

  # THE COUNT GOES THE OTHER WAY, and it is the one metric that does.
  test "closed-set misses falling reads as better" do
    row = compare(closed_set_misses: [ [ 11, 12, 10, 11 ], [ 3, 4, 2, 3 ] ])
          .find { |candidate| candidate.metric == :closed_set_misses }

    assert row.improved?, "fewer wrong records is better, and it is the only figure here that falls to improve"
    assert_equal "BETTER", row.direction
    assert_includes Eval::Classifier::Result::LOWER_IS_BETTER, :closed_set_misses
  end

  test "three repetitions a side cannot reach a verdict, however clean the separation" do
    row = compare(strict_accuracy: [ [ 0.10, 0.11, 0.12 ], [ 0.90, 0.91, 0.92 ] ])
          .find { |candidate| candidate.metric == :strict_accuracy }

    assert_predicate row.verdict, :inconclusive?,
                     "at 3 a side the smallest attainable p is 0.100 -- see Eval::Noise::MIN_RUNS"
  end

  test "two runs of the same numbers are never called real" do
    values = [ 0.93, 0.94, 0.92, 0.93 ]
    row = compare(strict_accuracy: [ values, values ]).find { |candidate| candidate.metric == :strict_accuracy }

    assert_not_predicate row.verdict, :real?
    assert_equal "unchanged", row.direction
  end

  # THE CAPTAIN'S INSTRUCTION OF 2026-09-04: a set records which model produced
  # it so that model A's set can be judged against model B's from the stored
  # scores alone. These four tests are that instruction.
  test "two sets with no model in common and one model each are paired and said to be a model comparison" do
    before = result({ "mistralai/mistral-medium-3.1" => { strict_accuracy: [ 0.93, 0.94, 0.92, 0.93 ] } })
    after = result({ "minimax/minimax-m3" => { strict_accuracy: [ 0.80, 0.81, 0.79, 0.80 ] } })
    comparison = Eval::Classifier::Comparison.new(before, after)
    out = StringIO.new

    assert_predicate comparison, :cross_model?
    assert_equal [ [ "mistralai/mistral-medium-3.1", "minimax/minimax-m3" ] ], comparison.pairs

    Eval::Classifier::Comparison.new(before, after, io: out).print
    assert_match(/THIS IS A MODEL COMPARISON/, out.string)
    assert_match(/mistral-medium-3\.1 \(before\)  ->  minimax\/minimax-m3 \(after\)/, out.string)
  end

  test "with several models a side and nothing in common it refuses rather than guessing the pair" do
    before = result({ "a" => { strict_accuracy: [ 0.9 ] * 4 }, "b" => { strict_accuracy: [ 0.9 ] * 4 } })
    after = result({ "c" => { strict_accuracy: [ 0.9 ] * 4 }, "d" => { strict_accuracy: [ 0.9 ] * 4 } })

    error = assert_raises(Eval::Classifier::Comparison::Unpairable) do
      Eval::Classifier::Comparison.new(before, after).pairs
    end
    assert_match(/BEFORE_MODEL=<model> AFTER_MODEL=<model>/, error.message)
  end

  test "a named pair picks one arm out of each set whatever else they hold" do
    before = result({ "a" => { strict_accuracy: [ 0.9 ] * 4 }, "b" => { strict_accuracy: [ 0.5 ] * 4 } })
    after = result({ "a" => { strict_accuracy: [ 0.9 ] * 4 }, "c" => { strict_accuracy: [ 0.7 ] * 4 } })
    comparison = Eval::Classifier::Comparison.new(before, after, before_model: "b", after_model: "c")

    assert_equal [ [ "b", "c" ] ], comparison.pairs
    row = comparison.verdicts("c", against: "b").find { |candidate| candidate.metric == :strict_accuracy }
    assert_in_delta 0.5, row.verdict.before.median
    assert_in_delta 0.7, row.verdict.after.median
  end

  # TWO SETS SCORED ON DIFFERENT CORPORA ARE NOT COMPARABLE, and the difference
  # between them is a difference between two files.
  test "a corpus digest mismatch is warned about above the verdicts" do
    before = result({ "a" => { strict_accuracy: [ 0.9 ] * 4 } }, digest: "aaaa")
    after = result({ "a" => { strict_accuracy: [ 0.5 ] * 4 } }, digest: "bbbb")
    out = StringIO.new

    Eval::Classifier::Comparison.new(before, after, io: out).print

    assert_not Eval::Classifier::Comparison.new(before, after).comparable_corpus?
    assert_match(/SCORED DIFFERENT CORPORA \(aaaa vs bbbb\)/, out.string)
  end

  test "the same corpus digest on both sides is not warned about" do
    before = result({ "a" => { strict_accuracy: [ 0.9 ] * 4 } }, digest: "same")
    after = result({ "a" => { strict_accuracy: [ 0.5 ] * 4 } }, digest: "same")
    out = StringIO.new

    Eval::Classifier::Comparison.new(before, after, io: out).print

    assert_predicate Eval::Classifier::Comparison.new(before, after), :comparable_corpus?
    assert_no_match(/DIFFERENT CORPORA/, out.string)
  end

  test "a model on only one side is named and not compared" do
    before = result({ "a" => { strict_accuracy: [ 0.9 ] * 4 } })
    after = result({ "a" => { strict_accuracy: [ 0.9 ] * 4 }, "b" => { strict_accuracy: [ 0.9 ] * 4 } })
    out = StringIO.new

    Eval::Classifier::Comparison.new(before, after, io: out).print

    assert_equal [ "a" ], Eval::Classifier::Comparison.new(before, after).arms
    assert_match(/only one side and therefore not compared: b/, out.string)
  end

  private

  def compare(figures)
    before = result({ "m" => figures.transform_values(&:first) })
    after = result({ "m" => figures.transform_values(&:last) })

    Eval::Classifier::Comparison.new(before, after).verdicts("m")
  end

  # A `Result` built out of nothing but the numbers. `Stored` reads a persisted
  # row, and a persisted row is what a comparison always has -- so a fixture
  # made of rows is the honest fixture here.
  def result(arms, digest: nil)
    passes = arms.flat_map do |arm, figures|
      length = figures.values.map(&:size).max
      (0...length).map do |index|
        row = { "arm" => arm, "rep" => index + 1, "readings" => [] }
        Eval::Classifier::Result::METRICS.each_key do |metric|
          row[metric.to_s] = figures.key?(metric) ? figures.fetch(metric)[index] : 0
        end
        Eval::Classifier::Result::Stored.new(row)
      end
    end

    Eval::Classifier::Result.new(name: "fixture", corpus_size: 300, corpus_digest: digest,
                                 arms: arms.keys, reps: passes.size / arms.size, passes: passes)
  end
end
