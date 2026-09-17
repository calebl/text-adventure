# Offline: replay the original physical-after answers through the unchanged
# full-turn evaluator, accepting only the classifier instructions difference.
# No provider client is reached. All current requests become an inspectable
# fixture manifest; this is preparation and cannot count as an after reading.
require_relative "support"
PhysicalConfirmation.empty_database!
raise "Preflight requires test environment" unless Rails.env.test?
root = PhysicalConfirmation::ROOT
original = PhysicalConfirmation::ORIGINAL
before = JSON.parse(original.join("physical-after.json").read)
checking_gate = ENV["PHYSICAL_GATE_CHECK"] == "1"
rows = checking_gate ? JSON.parse(root.join("requests.json").read).fetch("samples") : before.fetch("results")
PhysicalConfirmation.gate = PhysicalConfirmation::Gate.new(rows, capture: !checking_gate)

module PhysicalOffline
  Response = Data.define(:content)
  class << self
    attr_accessor :remaining
  end

  module Conversation
    def ask(prompt, **)
      row = PhysicalOffline.remaining.shift or raise PhysicalConfirmation::Halt, "Unrecorded provider request"
      answer = row.fetch("raw_answer")
      messages.create!(role: "user", content: prompt)
      if answer.is_a?(Hash) || answer.is_a?(Array)
        messages.create!(role: "assistant", content_raw: answer)
      else
        messages.create!(role: "assistant", content: answer)
      end
      ReviewEvalBudget.calls << row.dup
      response = Response.new(content: answer)
      yield response if block_given?
      response
    end
  end
end

PhysicalOffline.remaining = before.fetch("results").flat_map { |row| row.fetch("calls") }.dup
RubyLLM.config.openrouter_api_key = "offline-recorded-answer"
RubyLLM.config.openrouter_api_base = "http://127.0.0.1:1"
BaseAgent.define_singleton_method(:default_model_options) do
  [ { model: ReviewEvalBudget::MODEL, provider: :openrouter, assume_model_exists: false } ]
end
ReviewEvalBudget.define_singleton_method(:install!) { }
Chat.prepend(PhysicalOffline::Conversation)
PhysicalConfirmation.install!
ENV["EVAL_BUDGET_HELPER"] = PhysicalConfirmation::HELPER.to_s
ENV["EVAL_PREFLIGHT"] = "0"
ENV["EVAL_SOURCE_SHA"] = "offline-preflight"
ENV["EVAL_ARM"] = PhysicalConfirmation::LABEL
ENV["REPS"] = "4"
ENV["OUT"] = "/tmp/ta-physical-classifier-revised-20260910-preflight-results.json"
load original.join("evaluate.rb")
raise "Unplayed baseline receipts" unless PhysicalOffline.remaining.empty?
replay = JSON.parse(File.read(ENV.fetch("OUT")))
fields = %w[before after narration refusal resolved_action fallback interactions error]
replay.fetch("results").zip(before.fetch("results")).each do |actual, old|
  raise "Replay changed engine outcome" unless actual.slice(*fields) == old.slice(*fields)
end
requests = PhysicalConfirmation.gate.requests.dup
samples = before.fetch("results").map do |row|
  row.slice("case", "rep", "line", "before").merge("calls" => requests.shift(row.fetch("calls").length))
end
File.write(root.join("requests.json"), JSON.pretty_generate(
  endpoint: "https://openrouter.ai/api/v1/chat/completions", model: ReviewEvalBudget::MODEL,
  provider: ReviewEvalBudget::PROVIDER, repetitions: 4, turn_count: 28, max_calls: 60,
  content: "Fixed fictional Cal/Maren market fixtures only. Subsequent narrator text uses the fresh fixture answer/engine receipt, through the frozen actual builders.",
  samples: samples) + "\n")
calls = before.fetch("results").flat_map { |row| row.fetch("calls") }
source = PhysicalConfirmation.source
estimate = calls.sum { |call| call.fetch("registry_cost_usd") }
ledger = JSON.parse(File.read("/tmp/text-adventure-live-eval-20260909/budget.json"))
manifest = {
  source_commit: `git rev-parse HEAD`.strip, source: source,
  source_sha256: Digest::SHA256.hexdigest(JSON.generate(source)),
  requests_sha256: Digest::SHA256.file(root.join("requests.json")).hexdigest,
  baselines: %w[physical-before.json physical-after.json manual-audit.json comparison.json].to_h { |file| [ file, Digest::SHA256.file(original.join(file)).hexdigest ] },
  isolated_database: PhysicalConfirmation::DATABASE, model: ReviewEvalBudget::MODEL, provider: ReviewEvalBudget::PROVIDER,
  replayed_turns: 28, replayed_requests: 60, changed_requests: { classifier_instructions_only: 28 },
  request_guard_mode: checking_gate ? "live pre-send guard, with stored answers returned offline" : "capture exact current requests against original receipts",
  engine_states_and_outcomes_match: true, prior_actual_registry_usd: estimate,
  planning_allowance_usd: 0.10, shared_ceiling_usd: ReviewEvalBudget::LIMIT_MICROS.fdiv(1_000_000),
  shared_accounted_usd_at_preflight: ledger.fetch("entries").sum { |row| row.fetch("accounted_micros") }.fdiv(1_000_000),
  pricing: calls.first.fetch("registry_rates"), budget_helper: PhysicalConfirmation::HELPER.relative_path_from(Rails.root).to_s,
  authorization: "Prepared offline only. Explicit destination approval remains pending; no live run has been launched."
}
File.write(root.join("preflight.json"), JSON.pretty_generate(manifest) + "\n")
puts JSON.generate(manifest.except(:source, :baselines, :pricing))
