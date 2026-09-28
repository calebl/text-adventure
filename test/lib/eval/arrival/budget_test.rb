require "test_helper"

class Eval::Arrival::BudgetTest < ActiveSupport::TestCase
  test "unknown charges retain reservations and a full ledger refuses another request" do
    Dir.mktmpdir do |dir|
      ledger = Eval::Arrival::Budget::Ledger.new(File.join(dir, "budget.json"))
      token = ledger.reserve!(label: "unknown", input_cap: 1000)
      ledger.settle!(token, {})
      entry = ledger.snapshot.fetch("entries").first
      assert_equal "unknown", entry.fetch("state")
      assert_equal entry.fetch("reserved_micros"), entry.fetch("accounted_micros")
      assert_raises(Eval::Arrival::Budget::Halt) { ledger.reserve!(label: "too large", input_cap: 1_000_000) }
    end
  end

  test "streamed usage is retained when optional billing body is empty or malformed" do
    raw_type = Data.define(:body)
    [ "", "{broken" ].each do |body|
      receipt = Eval::Arrival::Budget.usage(RubyLLM::Message.new(role: :assistant, content: "{}",
        tokens: RubyLLM::Tokens.new(input: 100, output: 30), raw: raw_type.new(body: body), model: Eval::Arrival.model))
      assert_equal Eval::Arrival.model, receipt[:actual_model]
      assert_equal 100, receipt[:input_tokens]
      assert_equal 30, receipt[:output_tokens]
      assert_nil receipt[:provider_cost_usd]
      assert_operator receipt[:usage_upper_micros], :>, 0
    end
  end

  test "the output cap and the no-fallback route reach a persisted chat's request options" do
    previous_key = RubyLLM.config.openrouter_api_key
    RubyLLM.config.openrouter_api_key ||= "offline-arrival-test"
    chat = Chat.create!(model: Eval::Arrival.model, provider: "openrouter")
    Eval::Arrival::Budget.cap!(chat)
    assert_equal({ max_tokens: Eval::Arrival::Budget::MAX_OUTPUT_TOKENS, provider: { allow_fallbacks: false } },
                 chat.to_llm.instance_variable_get(:@provider_options))
  ensure
    RubyLLM.config.openrouter_api_key = previous_key
  end

  test "the receipt keeps the schema the engine wrote as well as a schema class's" do
    engine = { "name" => "Scene::Schema", "description" => nil, "schema" => { "type" => "object" } }
    assert_equal engine, Eval::Arrival::Budget.schema_json(Eval::EngineCalls::Schema.new(engine))
    assert_equal Scene::Schema.new.to_json_schema, Eval::Arrival::Budget.schema_json(Scene::Schema)
    assert_nil Eval::Arrival::Budget.schema_json(nil)
  end
end
