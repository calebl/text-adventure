require "test_helper"

# THE VERIFY-NOT-TRUST RULES, OFFLINE -- no chat is ever built here, so no
# network call and no database row. `Eval::Classifier::ToolAgent` only differs
# from `BaseAgent` in three private seams (`#build_chat`, `#verify_schema_honored!`,
# and the two prose checks turned off), and this tests those seams directly
# against a stand-in response, the same way `FakeAgent` stands in for a real
# `RubyLLM::Chat` response elsewhere in this suite.
class Eval::Classifier::ToolAgentTest < ActiveSupport::TestCase
  Response = Struct.new(:content)
  ToolResponse = Struct.new(:content, :tool_calls)

  MODEL_OPTIONS = [ { provider: :openrouter, model: "mistralai/mistral-medium-3.1", assume_model_exists: true } ].freeze

  test "before with_schema is called there is no tool to honor, exactly as the schema path has no schema yet" do
    agent = Eval::Classifier::ToolAgent.new(shape: :tool, model_options: MODEL_OPTIONS)

    assert_nil agent.send(:verify_schema_honored!, Response.new("prose"))
  end

  # SHAPE B'S TOOL CARRIES `intent`, `target` AND `also_named`, THE SAME THREE
  # THE SCHEMA CALL DOES -- so it is verified the same two ways
  # `BaseAgent#verify_schema_honored!` verifies a schema'd call: the content is
  # a `Hash`, and none of the three required fields are missing.
  test "shape B requires all three fields" do
    agent = Eval::Classifier::ToolAgent.new(shape: :tool, model_options: MODEL_OPTIONS)
    agent.with_schema(Playthrough::IntentSchema.for(%w[north]))
    agent.instance_variable_set(:@required_keys, %w[intent target also_named])

    assert_raises(BaseAgent::SchemaIgnoredError) { agent.send(:verify_schema_honored!, Response.new("prose")) }
    assert_raises(BaseAgent::SchemaIgnoredError) do
      agent.send(:verify_schema_honored!, Response.new({ "intent" => "move", "target" => "north" }))
    end
    assert_nil agent.send(:verify_schema_honored!,
                          Response.new({ "intent" => "move", "target" => "north", "also_named" => "nothing" }))
  end

  # SHAPE C'S TOOLS CARRY NO `intent` FIELD OF THEIR OWN -- `Eval::Classifier::ToolShapes`
  # injects it from the tool's own name, which cannot be missing -- so only
  # `target`/`also_named` are asked for here.
  test "shape C requires only target and also_named" do
    agent = Eval::Classifier::ToolAgent.new(shape: :tools, model_options: MODEL_OPTIONS)
    agent.with_schema(Playthrough::IntentSchema.for(%w[north]))
    agent.instance_variable_set(:@required_keys, %w[target also_named])

    assert_raises(BaseAgent::SchemaIgnoredError) do
      agent.send(:verify_schema_honored!, Response.new({ "intent" => "move", "target" => "north" }))
    end
    assert_nil agent.send(:verify_schema_honored!,
                          Response.new({ "intent" => "move", "target" => "north", "also_named" => "nothing" }))
  end

  test "tool responses expose first-generation arguments as classifier content" do
    agent = Eval::Classifier::ToolAgent.new(shape: :tools, model_options: MODEL_OPTIONS)
    call = RubyLLM::ToolCall.new(id: "call-1", name: "move",
                                 arguments: { "target" => "north", "also_named" => "nothing" })
    response = ToolResponse.new(nil, { call.id => call })

    exposed = agent.send(:expose_parsed_schema_content, response)

    assert_equal({ "target" => "north", "also_named" => "nothing", "intent" => "move" }, exposed.content)
    assert_nil response.content
  end

  # THE TWO PROSE-REFUSAL CHECKS ARE UNSCHEMA'D-CALL CHECKS -- `Scene::Narrator`'s
  # shape, not this one -- and a tool-shaped classifier call is closed exactly
  # as the schema call is, so it skips them the same way `@schema` present
  # already skips them on that path.
  test "the two prose-refusal checks are always skipped" do
    agent = Eval::Classifier::ToolAgent.new(shape: :tool, model_options: MODEL_OPTIONS)

    assert_nil agent.send(:verify_not_refused!, Response.new("I won't do that."))
    assert_nil agent.send(:verify_no_crisis_response!, Response.new("call this hotline"))
  end
end
