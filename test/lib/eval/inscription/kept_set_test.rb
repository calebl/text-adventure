require "test_helper"

# Explicitly read db/eval, never the local set that happened to be bought here.
# Every kept answer can be re-scored offline; the full normalized requests pin
# system, user context and emitted schema, rather than only constant names.
class Eval::Inscription::KeptSetTest < ActiveSupport::TestCase
  def kept
    @kept ||= JSON.parse(File.read(Eval.kept_root.join(Eval::Inscription::BASELINE, Eval::Inscription::RESULTS)))
  end

  test "the kept set is a complete baseline for the current fixed requests" do
    requests = EngineSweep.without_a_model { Eval::Inscription.requests }
    assert_equal Eval::Inscription.digest, kept.fetch("corpus_digest")
    assert_equal Eval::RequestIdentity.of(requests), kept.fetch("request_identity")
    assert_equal requests.transform_values { |request| Eval::RequestIdentity.of(request) }, kept.fetch("case_identities")
    assert_equal Eval::Noise::MIN_RUNS, kept.fetch("reps")
    assert_equal "mistralai/mistral-medium-3.1", kept.fetch("model")
    assert_equal requests.size * kept.fetch("reps"), kept.fetch("rows").size
    kept.fetch("rows").group_by { |row| row.fetch("rep") }.each_value do |rows|
      assert_equal requests.keys.sort, rows.map { |row| row.fetch("id") }.sort
    end
    kept.fetch("rows").each do |row|
      assert_equal Eval::RequestIdentity.of(requests.fetch(row.fetch("id"))), Eval::RequestIdentity.of(row.fetch("request"))
      assert_equal 1, row.fetch("receipts").size
      assert_equal kept.fetch("model"), row.fetch("receipts").sole.fetch("model")
      assert row.key?("human_fit")
      assert row.key?("human_note")
      assert_equal row["text"], row["template_text"] unless row["error"]
    end
  end

  test "receipts reproduce cost within the authorized cap and board works offline" do
    price = kept.fetch("estimate").fetch("price")
    dollars = kept.fetch("rows").sum do |row|
      amount = row.fetch("receipts").sum do |receipt|
        input = receipt.values_at("input_tokens", "cached_tokens", "cache_creation_tokens").sum
        (input * price.fetch("input_per_million") + receipt.fetch("output_tokens") * price.fetch("output_per_million")) / 1_000_000.0
      end
      assert_in_delta amount, row.fetch("dollars"), 1e-10
      amount
    end
    assert_operator dollars, :>, 0
    assert_operator dollars, :<, 2
    board = Eval::Inscription::Report.board(kept).join("\n")
    assert_includes board, "human_fit=unjudged"
    assert_includes board, "held-out:"
    assert_includes board, "tuning:"
    assert_includes Eval::MEASUREMENT_FILES, "db/eval/#{Eval::Inscription::BASELINE}/#{Eval::Inscription::RESULTS}"
  end
end
