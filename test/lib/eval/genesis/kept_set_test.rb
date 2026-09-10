require "test_helper"

# The kept readings are the free before side of a future prompt comparison.
# No defect rate is prescribed: this pins provenance and coverage, not success.
class Eval::Genesis::KeptSetTest < ActiveSupport::TestCase
  def kept = @kept ||= Eval::Genesis::Result.load(Eval.kept_root.join(Eval::Genesis::BASELINE))

  test "the kept baseline identifies today's corpus and every emitted request" do
    assert_equal Eval::Genesis.digest, kept.corpus_digest
    assert_equal Eval::Genesis::Version.offline, kept.request_digests
    assert_equal Eval::Noise::MIN_RUNS, kept.reps
    assert_equal kept.reps, kept.passes.size
    assert kept.document["request_stable"]
    kept.rows.each do |row|
      assert_equal Eval::Genesis::Version.digest(row.fetch("request")), row.fetch("request_digest")
      assert_equal kept.request_digests.dig(row["id"], row["call"]), row["request_digest"]
    end
  end

  test "all paid boundaries have receipts from the pinned model within the cap" do
    assert_equal [ "mistralai/mistral-medium-3.1" ], kept.arms
    assert_equal kept.arms, kept.rows.map { |row| row["answered_by"] }.uniq
    assert_equal 0, kept.receipt_missing
    assert_operator kept.cost, :>, 0
    assert_operator kept.cost, :<=, Eval::Genesis::Bench::SPEND_CEILING
    assert_operator kept.document["estimate_usd"], :>=, kept.cost
    expected = kept.request_digests.sum { |_id, calls| calls.size }
    kept.passes.each do |pass|
      assert_equal expected, pass.fetch("readings").size
      scorer = Eval::Genesis::Scorer.new(pass.fetch("readings"))
      Eval::Genesis::Scorer::CHECKS.each_key do |code|
        assert_operator scorer.judgeable_for(code), :>, 0, "#{code} was not measured"
      end
    end
  end

  test "offline board and null comparison read the kept data without a key" do
    table = Eval::Genesis::Board.new(kept).lines.join("\n")
    assert_includes table, "record fidelity only"
    assert_includes table, "quest quality: unavailable"
    comparison = Eval::Genesis::Comparison.new(kept, kept).lines.join("\n")
    assert_includes comparison, "NOISE"
    assert_not_includes comparison, "REAL ("
    assert_includes Eval::MEASUREMENT_FILES, "db/eval/#{Eval::Genesis::BASELINE}/#{Eval::Genesis::RESULTS}"
  end
end
