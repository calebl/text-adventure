require "test_helper"

# WHAT A RELAYED CALL COSTS, by what is known when it ends.
class RelayReceiptTest < ActiveSupport::TestCase
  MODEL = BaseAgent::REMOTE_MODEL_IDS.first

  setup { create(:model, model_id: MODEL, pricing: { "text_tokens" => { "standard" => { "input_per_million" => 1, "output_per_million" => 10 } } }) }

  def receipt(**attributes) = create(:relay_receipt, reserved_usd: BigDecimal("0.05"), **attributes)

  test "a reported cost is kept, unless the registry prices the tokens dearer" do
    cheap = receipt.settle!(upstream_status: 200, usage: { "prompt_tokens" => 1_000, "completion_tokens" => 100, "cost" => 0.003 })
    assert_equal [ "closed", "usage", BigDecimal("0.003") ], [ cheap.status, cheap.cost_source, cheap.cost_usd ]

    # 1,000 x 1 + 100 x 10 per million = 0.002, above a reported 0.0001.
    under = receipt.settle!(upstream_status: 200, usage: { "prompt_tokens" => 1_000, "completion_tokens" => 100, "cost" => 0.0001 })
    assert_equal BigDecimal("0.002"), under.cost_usd
  end

  test "tokens without a cost are priced from the registry" do
    settled = receipt.settle!(upstream_status: 200, usage: { "prompt_tokens" => 2_000, "completion_tokens" => 0 })
    assert_equal BigDecimal("0.002"), settled.cost_usd
  end

  test "an upstream error with no usage is not charged, and anything else unknown costs the reservation" do
    assert_equal [ "declined", 0 ], receipt.settle!(upstream_status: 429, usage: nil).then { [ it.cost_source, it.cost_usd ] }
    assert_equal [ "reservation", BigDecimal("0.05") ], receipt.settle!(upstream_status: 200, usage: nil).then { [ it.cost_source, it.cost_usd ] }
    assert_equal [ "reservation", BigDecimal("0.05") ], receipt.settle!(upstream_status: nil, usage: nil).then { [ it.cost_source, it.cost_usd ] }
    assert_equal "reservation", receipt.settle!(upstream_status: 200, usage: "garbage").cost_source
  end

  test "a decision costs what the hosted engine charges one, raised to a dearer report" do
    decision = receipt(route: "decisions", model: SystemOneAgent::OPENROUTER_MODEL)
    assert_equal SystemOneReceipt::COST_PER_REQUEST_USD, decision.settle!(upstream_status: 200, usage: { "cost" => 0.0001 }).cost_usd
    dear = receipt(route: "decisions", model: SystemOneAgent::OPENROUTER_MODEL)
    assert_equal BigDecimal("0.01"), dear.settle!(upstream_status: 200, usage: { "cost" => 0.01 }).cost_usd
  end

  test "a receipt settles once" do
    settled = receipt.settle!(upstream_status: 200, usage: { "cost" => 0.001 })
    settled.settle!(upstream_status: 500, usage: nil)
    assert_equal BigDecimal("0.001"), settled.reload.cost_usd
  end

  test "it keeps numbers only" do
    assert_empty RelayReceipt.column_names.grep(/body|prompt|message|content|key|header/)
  end
end
