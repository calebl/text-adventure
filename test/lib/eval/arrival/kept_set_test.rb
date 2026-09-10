require "test_helper"

class Eval::Arrival::KeptSetTest < ActiveSupport::TestCase
  test "kept set covers every fixed request at the minimum repetitions on one pinned model" do
    data = JSON.parse(Eval::Arrival::BASELINE.join(Eval::Arrival::RESULTS).read)
    assert_equal Eval::Arrival.digest, data.fetch("corpus_digest")
    assert_equal Eval::Arrival.model, data.fetch("model")
    assert_operator data.fetch("reps"), :>=, Eval::Noise::MIN_RUNS
    requests = Eval::Arrival.cases.to_h do |kase|
      [ kase.fetch("id"), Eval::Arrival::Stage.open(kase) { |stage| stage.request } ]
    end
    groups = data.fetch("rows").group_by { |r| r.fetch("rep") }
    assert_equal (1..data.fetch("reps")).to_a, groups.keys.sort
    groups.each_value do |rows|
      assert_equal requests.keys.sort, rows.map { |r| r.fetch("id") }.sort
      rows.each do |row|
        assert_nil row["error"], row["error"]
        assert_equal [ requests.fetch(row.fetch("id")) ], row.fetch("requests")
        assert_equal Eval::RequestIdentity.of(row.fetch("requests")), row.fetch("request_identity")
        assert_equal 1, row.fetch("calls").size
        call = row.fetch("calls").first
        assert_equal Eval::Arrival.model, call.fetch("actual_model")
        assert_equal "openrouter", call.fetch("provider")
        assert_operator call.fetch("input_tokens"), :>, 0
        assert_operator call.fetch("output_tokens"), :>, 0
        assert_operator call.fetch("provider_cost_usd"), :>, 0
        assert_equal row.fetch("requests").first.fetch("schema"), call.fetch("schema")
      end
    end
    ledger = data.fetch("budget")
    assert_equal data.fetch("rows").size + data.fetch("superseded_rows", []).size, ledger.fetch("entries").size
    assert_operator ledger.fetch("entries").sum { |r| r.fetch("accounted_micros") }, :<=, 2_000_000
    assert ledger.fetch("entries").all? { |e| e.fetch("state") == "settled" }
    result = Eval::Arrival::Result.new(data)
    assert result.compare(result).all? { |metric| metric.fetch(:outcome) == :noise }
    assert_includes result.board.join("\n"), "unavailable (this response has no annotation)"
  end

  test "schema system user and replay history independently move the identity" do
    request = { "system" => "system", "user" => "user", "schema" => Scene::Schema.new.to_json_schema, "history" => [] }
    original = Eval::RequestIdentity.of([ request ])
    request.each_key do |key|
      changed = request.merge(key => "changed")
      refute_equal original, Eval::RequestIdentity.of([ changed ])
    end
  end
end
