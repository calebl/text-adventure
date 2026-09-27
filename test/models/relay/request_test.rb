require "test_helper"

# WHAT THE RELAY WILL FORWARD, and what it holds against a call before it does.
class Relay::RequestTest < ActiveSupport::TestCase
  MODEL = BaseAgent::REMOTE_MODEL_IDS.first

  setup { create(:model, model_id: MODEL, pricing: { "text_tokens" => { "standard" => { "input_per_million" => 0.4, "output_per_million" => 2 } } }) }

  def chat(**fields) = { model: MODEL, messages: [ { role: "user", content: "look" } ] }.merge(fields).to_json

  def refusal(route = :chat_completions, raw)
    assert_raises(Relay::Request::Invalid) { Relay::Request.new(route, raw) }
  end

  test "every engine model is allowed on the chat route, and only the pinned Jev on the decisions route" do
    BaseAgent::REMOTE_MODEL_IDS.each { |model| assert_equal model, Relay::Request.new(:chat_completions, chat(model: model)).model }
    decision = { model: SystemOneAgent::OPENROUTER_MODEL, state: {}, questions: { a: {} } }
    assert_equal SystemOneAgent::OPENROUTER_MODEL, Relay::Request.new(:decisions, decision.to_json).model

    refusal(chat(model: SystemOneAgent::OPENROUTER_MODEL))
    refusal(:decisions, decision.merge(model: MODEL).to_json)
    refusal(:decisions, decision.merge(model: SystemOneAgent::TYPESAFE_MODEL).to_json)
  end

  test "an environment override of the front model does not widen the allowlist" do
    ENV["OPENROUTER_MODEL"] = "openai/gpt-5-pro"
    refusal(chat(model: "openai/gpt-5-pro"))
  ensure
    ENV.delete("OPENROUTER_MODEL")
  end

  test "the fields the engine's own requests carry are accepted" do
    schema = { type: "json_schema", json_schema: { name: "reply", schema: { type: "object" } } }
    tools = [ { type: "function", function: { name: "look", parameters: {} } } ]
    request = Relay::Request.new(:chat_completions, chat(stream: false, temperature: 0.7, response_format: schema,
                                                         tools: tools, tool_choice: "auto", max_tokens: 400))
    assert_equal 400, JSON.parse(request.forwarded_body)["max_tokens"]
  end

  test "a request that is not one JSON object, or has no messages, is refused" do
    refusal("not json")
    refusal("[1, 2]")
    refusal({ model: MODEL }.to_json)
    refusal(:decisions, { model: SystemOneAgent::OPENROUTER_MODEL, state: {}, questions: {} }.to_json)
  end

  test "the forwarded chat carries the output ceiling, and a stream always asks for its usage" do
    sent = JSON.parse(Relay::Request.new(:chat_completions, chat(stream: true, stream_options: { include_usage: false })).forwarded_body)
    assert_equal Relay::Request::MAX_OUTPUT_TOKENS, sent["max_tokens"]
    assert_equal({ "include_usage" => true }, sent["stream_options"])
  end

  test "reading stops one byte past the ceiling, whatever the declared length says" do
    limit = Relay::Request::MAX_BYTES[:decisions]
    error = assert_raises(Relay::Request::Invalid) { Relay::Request.read(:decisions, StringIO.new("x" * (limit * 4))) }
    assert_equal 413, error.status

    error = assert_raises(Relay::Request::Invalid) { Relay::Request.read(:decisions, StringIO.new("{}"), content_length: limit + 1) }
    assert_equal 413, error.status
  end

  test "the reservation is the call's worst case: its bytes and overhead in, its ceiling out, at the registry price" do
    raw = chat(max_tokens: 1_000)
    expected = ((raw.bytesize + Relay::Request::MESSAGE_OVERHEAD_TOKENS) * BigDecimal("0.4") + 1_000 * 2) / 1_000_000
    assert_equal expected.round(6, BigDecimal::ROUND_UP), Relay::Request.new(:chat_completions, raw).reservation

    uncapped = chat
    assert_operator Relay::Request.new(:chat_completions, uncapped).reservation, :>, Relay::Request.new(:chat_completions, raw).reservation
  end

  test "a model the registry cannot price is reserved dearly" do
    Model.where(model_id: MODEL).update_all(pricing: {})
    dear = Player::Allowance::UNPRICED_PER_MILLION
    raw = chat
    expected = ((raw.bytesize + Relay::Request::MESSAGE_OVERHEAD_TOKENS) * dear[:input] + Relay::Request::MAX_OUTPUT_TOKENS * dear[:output]) / 1_000_000
    assert_equal expected.round(6, BigDecimal::ROUND_UP), Relay::Request.new(:chat_completions, raw).reservation
  end

  test "a decision is reserved at the price the hosted engine charges one" do
    decision = { model: SystemOneAgent::OPENROUTER_MODEL, state: {}, questions: { a: {} } }.to_json
    assert_equal SystemOneReceipt::COST_PER_REQUEST_USD, Relay::Request.new(:decisions, decision).reservation
  end
end
