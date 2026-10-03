require "test_helper"

class Eval::Dialogue::ResultTest < ActiveSupport::TestCase
  def row
    { "id" => "give-owned-key", "rep" => 1,
      "expected" => { "carries_key" => true }, "facts" => { "carries_key" => false },
      "narration" => "Maren hands you the key.", "reaction" => { "action" => "I agree." }, "calls" => [] }
  end

  test "state failure is independent from missing human judgment" do
    result = Eval::Dialogue::Result.new({ "rows" => [ row ] })
    assert_equal 1.0, result.passes.first["state_failure"]
    assert_nil result.passes.first["contradiction"]
    assert_equal 0, result.passes.first["judged"]
  end

  test "signed human annotations need the actual prose digest and a defensible excerpt" do
    annotation = { "contradiction" => true, "reason" => "A completed transfer contradicts possession.",
      "excerpt" => "hands you the key", "narration_digest" => Digest::SHA256.hexdigest(row["narration"]) }
    result = Eval::Dialogue::Result.new({ "rows" => [ row ] }, annotations: { "give-owned-key:1" => annotation })
    assert_equal 1.0, result.passes.first["contradiction"]
    [ annotation.merge("excerpt" => "invented"), annotation.merge("narration_digest" => "stale") ].each do |bad|
      assert_raises(ArgumentError) { Eval::Dialogue::Result.new({ "rows" => [ row ] }, annotations: { "give-owned-key:1" => bad }) }
    end
  end

  test "fallbacks and paid call errors are exchange failures even with correct state" do
    r = row.merge("facts" => { "carries_key" => true }, "fallback" => true)
    result = Eval::Dialogue::Result.new({ "rows" => [ r ] })
    assert_equal 0.0, result.passes.first["state_failure"]
    assert_equal 1.0, result.passes.first["exchange_failure"]
  end

  test "different corpora and incomplete repetitions cannot produce a verdict" do
    data = { "rows" => [ row ], "model" => "pinned", "corpus_digest" => "fixed", "reps" => 4 }
    left = Eval::Dialogue::Result.new(data)
    assert_raises(ArgumentError) { left.compare(Eval::Dialogue::Result.new(data.merge("corpus_digest" => "different"))) }
    assert_raises(ArgumentError) { left.compare(left) }
  end

  def bystander_row(narration, rep: 1)
    { "id" => "bystander-greets-over-a-promise", "rep" => rep, "expected" => {}, "facts" => {},
      "narration" => narration, "calls" => [] }
  end

  test "a bystander case counts the narrations that name the bystander, and only a bystander set has the figure" do
    rows = [ bystander_row("Maren hands you the key while Tobin nods to you."), bystander_row("Maren hands you the key.") ]
    result = Eval::Dialogue::Result.new({ "corpus" => "bystander", "rows" => rows })
    assert_equal 0.5, result.passes.first["bystander_named"]
    assert_includes result.metrics, "bystander_named"
    assert_equal 0.0, Eval::Dialogue::Result.new({ "corpus" => "bystander", "rows" => [ bystander_row("Tobinesque light.") ] })
                                           .passes.first["bystander_named"]

    main = Eval::Dialogue::Result.new({ "rows" => [ row ] })
    assert_not main.passes.first.key?("bystander_named")
    assert_equal Eval::Dialogue::Result::METRICS, main.metrics
  end

  test "the kept bystander set named its bystander in no narration" do
    kept = Eval::Dialogue::Result.load(Eval.kept_root.join("dialogue-bystander-2026-09-28"))
    assert_equal [ 0.0 ] * kept.data.fetch("reps"), kept.passes.map { |p| p["bystander_named"] }
  end

  test "a trial set is never compared" do
    data = { "rows" => [ row ], "model" => "pinned", "corpus_digest" => "fixed", "reps" => 1, "trial" => true }
    trial = Eval::Dialogue::Result.new(data)
    error = assert_raises(ArgumentError) { trial.compare(trial) }
    assert_match(/trial/, error.message)
  end

  # The owner's ruling: `none` changes nothing, so a follower asked to stay who
  # picks it has refused and keeps following. Only `stop_following` is staying.
  def stay(status, following:, npc_room:)
    { "id" => "stay-behind", "rep" => 1, "effect" => { "status" => status },
      "expected" => Eval::Dialogue.cases.find { |k| k.fetch("id") == "stay-behind" }.fetch("expected"),
      "facts" => { "carries_key" => false, "following" => following, "foe" => false,
        "npc_room" => npc_room, "player_room" => "Courtyard" },
      "narration" => "Maren shakes her head.", "calls" => [] }
  end

  def state_failure(*rows) = Eval::Dialogue::Result.new({ "rows" => rows }).passes.first["state_failure"]

  test "a follower asked to stay who chooses none still follows, and only an explicit stay stays" do
    assert_equal 0.0, state_failure(stay("none", following: true, npc_room: "Courtyard"))
    assert_equal 0.0, state_failure(stay("applied", following: false, npc_room: "Market"))
    assert_equal 1.0, state_failure(stay("none", following: false, npc_room: "Market"))
    assert_equal 1.0, state_failure(stay("applied", following: true, npc_room: "Courtyard"))
  end

  test "none is a refusal only of what the case asked, not a pass for every case" do
    assert_equal 1.0, state_failure(row.merge("effect" => { "status" => "none" }))
  end

  test "the kept sets' stay-behind refusals are no longer state failures" do
    kept = Eval::Dialogue::Result.load(Eval.kept_root.join(Eval::Dialogue::BASELINE))
    rows = kept.rows.select { |r| r.fetch("id") == "stay-behind" }
    assert rows.any? && rows.all? { |r| r.dig("effect", "status") == "none" && r.dig("facts", "following") }
    assert(rows.all? { |r| kept.checks(r).values.all? })
  end
end
