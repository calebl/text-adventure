require "test_helper"

class Eval::Genesis::StageTest < ActiveSupport::TestCase
  test "requests are fixed across repetitions and staged rows roll back" do
    before = [ Story.count, Character.count, Quest.count, Location.count, Chat.count ]
    first = Eval::Genesis::Version.offline
    assert_equal first, Eval::Genesis::Version.offline
    assert_equal before, [ Story.count, Character.count, Quest.count, Location.count, Chat.count ]
    assert_equal Eval::Genesis.corpus.cases.map(&:id).sort, first.keys.sort
  end

  test "society and retry carry fixed assistant history and live prompt builders" do
    %w[universe duplicate-name].each do |id|
      kase = Eval::Genesis.corpus.cases.find { |candidate| candidate.id == id }
      Eval::Genesis::Stage.open(kase) do |stage|
        request = stage.requests.last
        assert_equal %w[user assistant], request.history.map { |message| message["role"] }
        assert_kind_of Hash, request.history.last["content"]
        assert request.schema.new.to_json_schema.present?
        if id == "duplicate-name"
          assert_includes request.user, request.facts.fetch("retry_name")
          assert_includes request.facts.fetch("taken_names"), request.facts.fetch("retry_name")
        end
      end
    end
  end

  test "changing a schema description or history changes request identity" do
    Eval::Genesis::Stage.open(Eval::Genesis.corpus.cases.first) do |stage|
      original = stage.requests.first.identity
      changed = original.deep_dup
      changed["schema"]["schema"]["properties"]["title"]["description"] += " Changed."
      assert_not_equal Eval::Genesis::Version.digest(original), Eval::Genesis::Version.digest(changed)
      changed = original.merge("history" => [ { "role" => "assistant", "content" => "new upstream" } ])
      assert_not_equal Eval::Genesis::Version.digest(original), Eval::Genesis::Version.digest(changed)
    end
  end

  test "player body comes from the kernel and no cast is present at its boundary" do
    kase = Eval::Genesis.corpus.cases.find { |candidate| candidate.producer == "character" }
    Eval::Genesis::Stage.open(kase) do |stage|
      facts = stage.requests.sole.facts
      expected = Character::StatBlock.roll(story: kase.seed, at: stage.story.clock.to_i)
        .merge(level: Character::StatBlock::PROTAGONIST_LEVEL, hit_die: Character::StatBlock::PROTAGONIST_HIT_DIE)
      assert_equal expected.stringify_keys, facts["body"]
      assert_empty facts["taken_names"]
      assert_includes facts["races"], facts["race"]
    end
  end
end
