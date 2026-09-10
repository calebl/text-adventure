require "test_helper"

class Eval::Dialogue::BenchTest < ActiveSupport::TestCase
  def response(action)
    { "pre_thought" => "I understand.", "pre_feeling" => "calm, attentive",
      "action" => 'Maren nods. "Agreed."', "post_thought" => "I have answered.",
      "post_feeling" => "calm, resolved", "inner_resolution" => "I will keep my word.", "engine_action" => action }
  end

  def replay(kase, action)
    row = { "id" => kase.fetch("id"), "rep" => 1,
      "calls" => [ { "raw_answer" => response(action) }, { "raw_answer" => "Maren nods to you." } ] }
    Eval::Dialogue::Version.rebuild(row)
  end

  test "staging and both request passes repeat byte for byte without writing a world" do
    kase = Eval::Dialogue.cases.first
    before = [ Story.count, Playthrough.count, Item.count ]
    a = replay(kase, "give:910002")
    b = replay(kase, "give:910002")
    assert_nil a["error"]
    assert_equal 2, a["requests"].size
    assert_equal a["requests"], b["requests"]
    assert_equal a["request_digest"], b["request_digest"]
    assert_equal before, [ Story.count, Playthrough.count, Item.count ]
    assert a["facts"]["carries_key"]
    assert_equal [ "brass key" ], a["facts"]["world_items"]
  end

  test "all declared states are reachable through the production action gate" do
    actions = %w[give:910002 follow ceasefire none none stop_following give:910002 follow ceasefire]
    Eval::Dialogue.cases.zip(actions).each do |kase, action|
      row = replay(kase, action)
      assert_nil row["error"], row.inspect
      result = Eval::Dialogue::Result.new({ "rows" => [ row ] })
      assert result.checks(row).values.all?, "#{kase.fetch('id')}: #{row.fetch('facts')}"
    end
  end

  test "malformed and out of set actions change nothing and reach the narrator as rejection" do
    [ "give:garbage", "teleport", { "give" => 910002 }, nil ].each do |action|
      row = replay(Eval::Dialogue.cases.first, action)
      assert_equal "rejected", row.dig("effect", "status")
      assert_not row.dig("facts", "carries_key")
      assert_not row.dig("facts", "following")
      assert_not row.dig("facts", "foe")
      assert_includes row.fetch("requests").last.fetch("user"), "The proposed action was rejected"
    end
  end

  test "identity covers descriptors user system and replay history" do
    request = replay(Eval::Dialogue.cases.first, "none").fetch("requests")
    %w[system user schema history].each do |field|
      changed = request.deep_dup
      changed.first[field] = [ changed.first[field], "changed" ]
      assert_not_equal Eval::Dialogue::Version.digest(request), Eval::Dialogue::Version.digest(changed)
    end
  end

  test "an invalid reaction is a measured error and never applies a gift" do
    row = { "id" => Eval::Dialogue.cases.first.fetch("id"), "rep" => 1,
      "calls" => [ { "raw_answer" => response("give:910002").merge("action" => "") } ] }
    rebuilt = Eval::Dialogue::Version.rebuild(row)
    assert rebuilt["error"]
    assert_not rebuilt.dig("facts", "carries_key")
  end
end
