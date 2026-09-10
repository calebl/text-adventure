require "test_helper"

class Eval::Dialogue::BudgetTest < ActiveSupport::TestCase
  test "unknown charges retain reservations and a full ledger refuses another request" do
    Dir.mktmpdir do |dir|
      ledger = Eval::Dialogue::Budget::Ledger.new(File.join(dir, "budget.json"))
      token = ledger.reserve!(label: "unknown", input_cap: 1000)
      ledger.settle!(token, {})
      entry = ledger.snapshot.fetch("entries").first
      assert_equal "unknown", entry.fetch("state")
      assert_equal entry.fetch("reserved_micros"), entry.fetch("accounted_micros")
      assert_raises(Eval::Dialogue::Budget::Halt) { ledger.reserve!(label: "too large", input_cap: 1_000_000) }
    end
  end

  test "streamed usage is retained when optional billing body is empty or malformed" do
    raw_type = Data.define(:body)
    response_type = Data.define(:input_tokens, :output_tokens, :raw, :model_id)
    [ "", "{broken" ].each do |body|
      receipt = Eval::Dialogue::Budget.usage(response_type.new(input_tokens: 100, output_tokens: 30,
        raw: raw_type.new(body: body), model_id: Eval::Dialogue.model))
      assert_equal 100, receipt[:input_tokens]
      assert_equal 30, receipt[:output_tokens]
      assert_nil receipt[:provider_cost_usd]
      assert_operator receipt[:usage_upper_micros], :>, 0
    end
  end
end
