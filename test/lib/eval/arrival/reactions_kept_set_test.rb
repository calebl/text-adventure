require "test_helper"

# THE ROOM REACTING TO THE ARRIVAL, KEPT: the set the reactions corpus was
# bought as, rebuilt offline. Every case's request is today's, with the rows
# the engine's reactions step would have written held on the staged arrival.
class Eval::Arrival::ReactionsKeptSetTest < ActiveSupport::TestCase
  test "kept set covers every reaction case at the minimum repetitions on one pinned model" do
    data = JSON.parse(Eval::Arrival::Reactions::BASELINE.join(Eval::Arrival::RESULTS).read)
    assert_equal Eval::Arrival::Reactions.digest, data.fetch("corpus_digest")
    assert_equal Eval::Arrival::Reactions.model, data.fetch("model")
    assert_operator data.fetch("reps"), :>=, Eval::Noise::MIN_RUNS
    requests = Eval::Arrival::Reactions.cases.to_h do |kase|
      [ kase.fetch("id"), Eval::Arrival::Reactions::Stage.open(kase) { |stage| stage.request } ]
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
        assert_equal Eval::Arrival::Reactions.model, call.fetch("actual_model")
        assert_operator call.fetch("provider_cost_usd"), :>, 0
      end
    end
    # A reading the provider refused (a rate limit) was read again: the refused
    # one is kept as superseded, and its reservation stays unsettled, since no
    # receipt came back to settle it with.
    ledger = data.fetch("budget").fetch("entries")
    assert_equal data.fetch("rows").size + data.fetch("superseded_rows", []).size, ledger.size
    unsettled = ledger.reject { |entry| entry.fetch("state") == "settled" }
    assert_equal data.fetch("superseded_rows", []).size, unsettled.size
    assert data.fetch("superseded_rows", []).all? { |row| row.fetch("error").present? }
  end

  test "every reaction the case names is told in the block after the records, in id order" do
    Eval::Arrival::Reactions.cases.each do |kase|
      Eval::Arrival::Reactions::Stage.open(kase) do |stage|
        facts = stage.facts.fetch("reactions")
        assert_equal kase.fetch("reactions").size, facts.size, kase.fetch("id")
        assert facts.all? { |row| row.fetch("status") == "applied" }, kase.fetch("id")
        told = stage.request.fetch("user")[/## As You Come In\n[^\n]*\n(.*)\z/m, 1].to_s.lines.map(&:chomp).reject(&:empty?)
        assert_equal facts.map { |row| row.fetch("fact") }, told, kase.fetch("id")
      end
    end
  end

  test "the manifest names the set, so deleting it is a failing test" do
    assert_includes Eval::MEASUREMENT_FILES, "db/eval/#{Eval::Arrival::Reactions::BASELINE.basename}/#{Eval::Arrival::RESULTS}"
  end
end
