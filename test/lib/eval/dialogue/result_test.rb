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
end
