# Standalone offline tests. These deliberately define fake BaseAgent/Chat
# classes and never load Rails, RubyLLM's HTTP client or provider credentials.
require "minitest/autorun"
require "tmpdir"
require "ostruct"
require_relative "eval_budget"

module RubyLLM
  def self.config = (@config ||= OpenStruct.new(max_retries: 3))
end

class Chat
  def model
    OpenStruct.new(pricing: { "text_tokens" => { "standard" => { "input_per_million" => 0.4, "output_per_million" => 2.0 } } }, context_window: 131_072)
  end

  def messages = self
  def order(*) = []
  def with_params(**params) = (@params = params)
  attr_reader :params

  def ask(*)
    OpenStruct.new(content: "fixture answer", model_id: ReviewEvalBudget::MODEL,
                   input_tokens: 100, output_tokens: 20, cached_tokens: 10,
                   cache_creation_tokens: 0, thinking_tokens: 0,
                   cost: OpenStruct.new(total: 0.000081),
                   raw: OpenStruct.new(body: { "usage" => { "cost" => 0.00008 } }))
  end
end

class BaseAgent
  attr_reader :model_options, :schema, :instructions, :purpose
  def initialize(fail_verification: false, model_options: self.class.default_model_options)
    @model_options, @fail_verification = model_options, fail_verification
    @purpose, @instructions = "fixture", "A fixed instruction."
  end
  def chat = (@chat ||= Chat.new)
  def ask(prompt, **)
    result = chat.ask(prompt)
    raise "schema was rejected" if @fail_verification
    result
  end
end

class ReviewEvalBudgetTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("review-eval-budget-test")
    @path = File.join(@directory, "budget.json")
    @previous = ENV.to_h.slice("EVAL_LIVE", "EVAL_BUDGET_FILE", "OPENROUTER_API_KEY")
    ENV["EVAL_LIVE"], ENV["EVAL_BUDGET_FILE"], ENV["OPENROUTER_API_KEY"] = "1", @path, "offline-fixture-never-sent"
    ReviewEvalBudget.install!
    ReviewEvalBudget.label = "offline-test"
  end

  def teardown
    %w[EVAL_LIVE EVAL_BUDGET_FILE OPENROUTER_API_KEY].each { |key| @previous.key?(key) ? ENV[key] = @previous[key] : ENV.delete(key) }
    FileUtils.remove_entry(@directory)
  end

  def test_pins_one_arm_and_captures_actual_usage_before_schema_rejection
    agent = BaseAgent.new(fail_verification: true)
    assert_raises(RuntimeError) { agent.ask("A fixture prompt.") }
    receipt = ReviewEvalBudget.calls.fetch(0)
    assert_equal 100, receipt[:input_tokens]
    assert_equal 10, receipt[:cached_tokens]
    assert_equal 0.00008, receipt[:provider_cost_usd]
    assert_equal "RuntimeError", receipt[:error]
    assert_equal "fixture answer", receipt[:raw_answer]
    assert_equal 80, ReviewEvalBudget.ledger.snapshot.fetch("entries").fetch(0).fetch("accounted_micros")
    assert_equal 1, agent.model_options.size
    assert_equal 0, RubyLLM.config.max_retries
    assert_equal 2048, agent.chat.params.fetch(:max_tokens)
    assert_equal false, agent.chat.params.dig(:provider, :allow_fallbacks)
  end

  def test_unknown_failure_retains_full_reservation
    ticket = ReviewEvalBudget.ledger.reserve!(label: "timeout", input_cap: 2000)
    ReviewEvalBudget.ledger.settle!(ticket, {})
    entry = ReviewEvalBudget.ledger.snapshot.fetch("entries").fetch(0)
    assert_equal "unknown", entry.fetch("state")
    assert_equal entry.fetch("reserved_micros"), entry.fetch("accounted_micros")
  end

  def test_streamed_empty_or_sse_body_keeps_message_token_accounting
    [ "", "data: {\"choices\": []}\n\ndata: [DONE]\n", "{incomplete" ].each do |body|
      result = OpenStruct.new(model_id: ReviewEvalBudget::MODEL,
                              input_tokens: 100, output_tokens: 20,
                              cost: OpenStruct.new(total: 0.00008),
                              raw: OpenStruct.new(body: body))
      receipt = ReviewEvalBudget.usage(result)
      assert_nil receipt[:provider_cost_usd]
      assert_equal 100, receipt[:input_tokens]
      assert_equal 20, receipt[:output_tokens]
      assert_equal 900, receipt[:usage_upper_micros]
      assert_equal ReviewEvalBudget::MODEL, receipt[:actual_model]
      assert_equal "JSON::ParserError", receipt[:provider_cost_metadata_error] if body == "{incomplete"
    end
  end

  def test_independent_processes_share_one_ceiling
    pids = 12.times.map do
      fork do
        begin
          ReviewEvalBudget::Ledger.new(@path).reserve!(label: "child", input_cap: 60_000, output_cap: 2000)
          exit! 0
        rescue ReviewEvalBudget::Halt
          exit! 2
        end
      end
    end
    outcomes = pids.map { |pid| Process.wait2(pid).last.exitstatus }
    assert_equal 8, outcomes.count(0)
    assert_equal 4, outcomes.count(2)
    total = ReviewEvalBudget.ledger.snapshot.fetch("entries").sum { |row| row.fetch("accounted_micros") }
    assert_equal 2_720_000, total
    assert_operator total, :<=, ReviewEvalBudget::LIMIT_MICROS
  end

  def test_unsafe_arm_input_and_live_mode_fail_before_call
    assert_raises(ReviewEvalBudget::Halt) { BaseAgent.new(model_options: []).ask("fixture") }
    assert_raises(ReviewEvalBudget::Halt) { BaseAgent.new.ask("a" * 70_000) }
    ENV.delete("EVAL_LIVE")
    assert_raises(ReviewEvalBudget::Halt) { ReviewEvalBudget.install! }
    assert_empty ReviewEvalBudget.calls
  end
end
