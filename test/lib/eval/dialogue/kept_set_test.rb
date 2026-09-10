require "test_helper"

# A kept response rebuilds both requests on current records, without a key or
# provider. A future prompt/schema/receipt/history edit must fail this guard
# until evaluated; changing a hash alone cannot make replay agree.
class Eval::Dialogue::KeptSetTest < ActiveSupport::TestCase
  BASELINE = "dialogue-2026-09-10".freeze

  def kept = Eval::Dialogue::Result.load(Eval.kept_root.join(BASELINE))

  test "the standing set contains every repetition on the approved model" do
    result = kept
    result.validate_complete!
    assert_operator result.data.fetch("reps"), :>=, Eval::Noise::MIN_RUNS
    assert_equal Eval::Dialogue.model, result.data.fetch("model")
    assert_equal Eval::Dialogue.digest, result.data.fetch("corpus_digest")
    assert_equal Eval::Dialogue.cases.size * result.data.fetch("reps"), result.rows.size
    result.rows.each do |row|
      assert_equal 2, row.fetch("calls").size
      row.fetch("calls").each { |call| assert_equal Eval::Dialogue.model, call.fetch("actual_model") }
    end
  end

  test "every emitted request matches the stored identity and today's builders" do
    kept.rows.each do |row|
      assert_equal Eval::Dialogue::Version.digest(row.fetch("requests")), row.fetch("request_digest")
      rebuilt = Eval::Dialogue::Version.rebuild(row)
      assert_equal row.fetch("requests"), rebuilt.fetch("requests"), "#{row.fetch('id')}:#{row.fetch('rep')} changed"
      assert_equal row.fetch("facts"), rebuilt.fetch("facts")
      row.fetch("calls").zip(row.fetch("requests")).each do |call, request|
        assert_equal request, { "system" => call["instructions"], "user" => call["prompt"],
          "schema" => call["schema"], "history" => call["history"] }
      end
    end
  end

  test "receipts fit the authorized cap and annotations remain explicitly unavailable" do
    data = kept.data
    charged = data.fetch("budget").fetch("entries").sum { |e| e.fetch("accounted_micros") }
    assert_operator charged, :<=, Eval::Dialogue::Budget::LIMIT_MICROS
    assert kept.passes.all? { |p| p["contradiction"].nil? }
    assert_includes Eval::MEASUREMENT_FILES, "db/eval/#{BASELINE}/#{Eval::Dialogue::RESULTS}"
  end
end
