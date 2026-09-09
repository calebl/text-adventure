require "test_helper"

class InteractionAgentAgencyTest < ActiveSupport::TestCase
  setup do
    @game = create(:playthrough, :started)
    @npc = create(:character, story: @game.story, location: @game.current_location,
                             fullname: "Maren", nickname: "Maren", age: 32, sex: "female")
    create(:item, character: @npc, name: "brass key")
    Playthrough::Snapshot.new(@game).of_the_room!(@game.current_location)
    @key = @game.items_held_by(@npc).sole
  end

  test "the schema offers only current actions and preserves all reaction fields" do
    BaseAgent.stub(:new, FakeAgent.new) do
      schema = InteractionAgent.new(@npc, playthrough: @game).character_agent.schemas.last
      assert_equal Interaction::Schema.required_properties + [ :engine_action ], schema.required_properties
      Interaction::Schema.properties.each do |name, property|
        assert_equal property, schema.properties.fetch(name)
      end
      assert_equal [ "none", "give:#{@key.id}", "follow" ], schema.properties.fetch(:engine_action).fetch(:enum)
    end
  end

  test "an accepted gift is already in the player's hands when the narrator is called" do
    character = FakeAgent.new(reaction("give:#{@key.id}"))
    narrator = FakeAgent.new("Maren gives you the key.")
    original = narrator.method(:ask)
    observed = nil
    game, key = @game, @key
    narrator.define_singleton_method(:ask) do |*args, **kwargs, &block|
      observed = game.carried.include?(key)
      original.call(*args, **kwargs, &block)
    end
    queue = [ character, narrator ]
    exchange = BaseAgent.stub(:new, ->(*, **) { queue.shift }) do
      InteractionAgent.new(@npc, playthrough: @game).ask("Please return the key.")
    end

    assert observed
    assert_predicate exchange.effect, :applied?
    assert_includes narrator.prompts.sole, exchange.effect.fact
    assert_not_includes exchange.reaction.keys, :engine_action
  end

  test "an unsupported action produces a rejected fact and no invented state" do
    fake = FakeAgent.new(reaction("give:9999999"), "Maren has no crown to give you.")
    exchange = BaseAgent.stub(:new, fake) do
      InteractionAgent.new(@npc, playthrough: @game).ask("Give me the crown.")
    end

    assert_equal "rejected", exchange.effect.status
    assert_includes fake.prompts.last, "The proposed action was rejected"
    assert_empty @game.carried
    assert_equal @npc, @key.reload.character
  end

  test "a failed narrator discards its streamed fragments and keeps only the applied fact" do
    character = FakeAgent.new(reaction("give:#{@key.id}"))
    narrator = Object.new
    def narrator.ask(*)
      yield FakeAgent::Chunk.new("A sentence that must not escape.")
      raise BaseAgent::CrisisResponseError, "intercepted"
    end
    queue = [ character, narrator ]
    chunks = []
    exchange = BaseAgent.stub(:new, ->(*, **) { queue.shift }) do
      InteractionAgent.new(@npc, playthrough: @game).ask("The key, please.") { |part| chunks << part }
    end

    assert_predicate exchange, :fallback?
    assert exchange.safety_notice
    assert_equal [ exchange.narration ], chunks
    assert_not_includes chunks.join, "must not escape"
    assert_includes chunks.join, exchange.effect.fact
    assert_includes @game.carried, @key
  end

  test "only the accepted final prose is published after a streamed retry" do
    character = FakeAgent.new(reaction("none"))
    narrator = Object.new
    def narrator.ask(*)
      yield FakeAgent::Chunk.new("Rejected attempt that must not escape.")
      yield FakeAgent::Chunk.new("Maren nods.")
      FakeAgent::Response.new("Maren nods.")
    end
    queue = [ character, narrator ]
    chunks = []
    exchange = BaseAgent.stub(:new, ->(*, **) { queue.shift }) do
      InteractionAgent.new(@npc, playthrough: @game).ask("Hello.") { |part| chunks << part }
    end

    assert_not_predicate exchange, :fallback?
    assert_equal [ "Maren nods." ], chunks
  end

  test "a required reaction sanitized to blank is rejected before its gift can apply" do
    character = FakeAgent.new(reaction("give:#{@key.id}").merge("pre_feeling" => "🙂"))
    narrator = FakeAgent.new("Maren gives you the key.")
    queue = [ character, narrator ]
    assert_no_difference [ -> { Scene.count }, -> { Interaction.count }, -> { @game.npc_states.count } ] do
      BaseAgent.stub(:new, ->(*, **) { queue.shift }) do
        assert_raises(ActiveRecord::RecordInvalid) do
          InteractionAgent.new(@npc, playthrough: @game).ask("The key, please.")
        end
      end
    end

    assert_empty narrator.prompts
    assert_equal @npc, @key.reload.character
    assert_empty @game.carried
  end

  private

  def reaction(choice)
    Interaction::Schema.required_properties.to_h { |field| [ field.to_s, "A complete #{field} sentence." ] }
                       .merge("engine_action" => choice)
  end
end
