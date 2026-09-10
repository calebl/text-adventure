require "test_helper"

class Eval::Prompt::BranchesStageTest < ActiveSupport::TestCase
  test "every designated branch renders from records and survives unrelated IDs" do
    before = [ Story.count, Playthrough.count, Item.count, Playthrough::Blow.count, Playthrough::Toll.count ]
    captured = Eval::Prompt::Branches.capture
    assert_equal before, [ Story.count, Playthrough.count, Item.count, Playthrough::Blow.count, Playthrough::Toll.count ]
    create(:story)
    assert_equal captured, Eval::Prompt::Branches.capture

    assert_includes prompt(captured, "next_beat"), "The story is asking for: #{facts(captured, 'next_beat')['next_beat']}"
    facts(captured, "next_beat")["withheld"].each { |words| refute_includes prompt(captured, "next_beat"), words }
    assert_includes prompt(captured, "combat"), "Blows landed, recorded by the game:"
    assert_includes prompt(captured, "combat"), "and is fighting you"
    assert_equal [ 1, 1 ], facts(captured, "combat")["blows"].pluck("round")
    assert facts(captured, "combat")["bodies"].all? { |body| body["hp"].positive? }
    facts(captured, "combat")["blows"].each do |blow|
      assert_operator blow["damage"], :>=, 1
      assert_operator blow["damage"], :<=, blow["die"]
    end
    assert_includes prompt(captured, "toll"), "The place itself, recorded by the game:"
    assert_includes prompt(captured, "saved_toll"), "lost nothing"
    assert_equal 0, facts(captured, "saved_toll")["tolls"].sole["damage"]
    assert_equal 8, facts(captured, "throw")["throw"]["die"]
    assert_equal "struck", facts(captured, "throw")["throw"]["kind"]
    assert_includes prompt(captured, "throw"), "stone weight at Gorva the Wanderer and it hit them"
    assert_includes prompt(captured, "throw"), "NO LONGER CARRIED"
    assert_includes prompt(captured, "recap"), "Earlier, in order:"
    assert_includes prompt(captured, "recap"), facts(captured, "recap")["recap"]
    assert_includes prompt(captured, "wounded"), "hurt (5 of 8)"
    assert_includes prompt(captured, "dead_foe"), "dead: that was the blow that killed them"
    assert_predicate facts(captured, "plan")["plan"], :present?
    assert_includes prompt(captured, "plan"), facts(captured, "plan")["plan"]
    assert_equal Eval::Prompt.corpus("branches").by_shape.keys.sort, captured.keys.sort
  end

  test "rendered branch wording and schemas participate in versioned identity" do
    captured = Eval::Prompt::Branches.capture
    identity = Eval::Prompt::Branches.identity(captured)
    changed = captured.deep_dup
    changed["combat"]["request"][:user] += " A changed framing."
    assert_not_equal identity, Eval::Prompt::Branches.identity(changed)
    changed = captured.deep_dup
    changed["throw"]["request"][:schema] = { type: "object" }
    assert_not_equal identity, Eval::Prompt::Branches.identity(changed)
    assert_equal Eval::RequestIdentity::VERSION, identity["version"]
  end

  test "branches is a separate valid corpus" do
    assert_empty Eval::Prompt.corpus("branches").problems
    refute_equal Eval::Prompt.digest, Eval::Prompt.digest(Eval::Prompt.corpus("branches"))
  end

  private

  def prompt(captured, shape) = captured.fetch(shape).fetch("request").fetch(:user)
  def facts(captured, shape) = captured.fetch(shape).fetch("facts")
end
