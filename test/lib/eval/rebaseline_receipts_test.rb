require "test_helper"

# Kept receipt summaries are derived from the task's complete per-call ledger,
# including calls that the legacy scored-scene receipts leave out.
class Eval::RebaselineReceiptsTest < ActiveSupport::TestCase
  SETS = %w[prompt-2026-09-10 classifier-2026-09-10 prompt-ending-2026-09-10].freeze

  test "kept receipts account for every request and stay inside the task ceiling" do
    ledger = JSON.parse(Rails.root.join("doc/evidence/ta-bench-rebaseline-stale/receipts.json").read)
    grouped = ledger.fetch("calls").group_by { |row| row.fetch("set") }
    assert_equal SETS.sort, grouped.keys.sort
    assert_operator ledger.fetch("calls").sum { |row| row.fetch("accounted_usd") }, :<=, ledger.fetch("limit_usd")
    assert_equal 2.0, ledger.fetch("limit_usd")
    # These receipts belong to frozen historical sets. A later corpus can add
    # lines without retroactively adding calls to an already purchased run.
    measured = SETS.to_h do |name|
      filename = name.start_with?("classifier-") ? "classifier.json" : "prompt.json"
      result = JSON.parse(Eval.kept_root.join(name, filename).read)
      assert_equal Eval::Noise::MIN_RUNS, result.fetch("reps")
      [ name, result.fetch("corpus_size") * result.fetch("reps") + 1 ]
    end
    expected_calls = {
      SETS[0] => measured.fetch(SETS[0]),
      SETS[1] => measured.fetch(SETS[1]),
      SETS[2] => measured.fetch(SETS[2]) * 2
    }
    SETS.each do |name|
      file = "db/eval/#{name}/receipts.json"
      receipt = JSON.parse(Rails.root.join(file).read)
      rows = grouped.fetch(name)
      assert_equal expected_calls.fetch(name), rows.size
      assert_equal rows.size, receipt.fetch("calls_including_warmup_and_preludes")
      assert_equal rows.size, receipt.fetch("settled")
      assert_equal 0, receipt.fetch("unknown_or_reserved")
      assert_equal [ BaseAgent::REMOTE_MODEL_IDS.first ], receipt.fetch("actual_models")
      assert_in_delta rows.sum { |row| row.fetch("accounted_usd") }, receipt.fetch("accounted_usd")
      assert_in_delta rows.sum { |row| row.fetch("registry_cost_usd") }, receipt.fetch("registry_priced_usd")
      assert_includes Eval::MEASUREMENT_FILES, file
    end
  end
end
