require "test_helper"
require Rails.root.join("db/eval/physical-classifier-final-20260914/evaluate")

class Eval::Classifier::FinalStudyTest < ActiveSupport::TestCase
  test "the final comparison uses the revised matched before and suppresses incomparable latency" do
    before = Eval::Classifier::Result.load(FinalPhysicalClassifierStudy::BEFORE)
    after = Eval::Classifier::Result.new(name: "final-fixture", corpus_size: before.corpus_size,
      corpus_digest: before.corpus_digest, request_identity: before.request_identity,
      arms: before.arms, reps: before.reps, passes: before.passes, concurrency: 1)
    comparison = FinalPhysicalClassifierStudy.matched_comparison(after)
    assert_equal "physical-classifier-revised-20260910", comparison.fetch("before")
    assert_equal "final-fixture", comparison.fetch("after")
    assert_equal %i[latency_median latency_p95], comparison.fetch("suppressed_metrics")
    assert comparison.fetch("verdicts").all? { |row| row.fetch("direction") == "unchanged" && row.dig("verdict", :outcome) == :noise }
    assert_equal 1, FinalPhysicalClassifierStudy::CONCURRENCY
  end

  test "the final comparison refuses a changed corpus even when its size matches" do
    before = Eval::Classifier::Result.load(FinalPhysicalClassifierStudy::BEFORE)
    after = Eval::Classifier::Result.new(name: "changed-fixture", corpus_size: before.corpus_size,
      corpus_digest: "different labels", arms: before.arms, reps: before.reps, passes: before.passes)
    assert_raises(RuntimeError) { FinalPhysicalClassifierStudy.matched_comparison(after) }
  end
end
