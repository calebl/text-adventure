# Offline replay of all original full-Turn receipts through the final source.
# The shared payload gate runs before stored answers are supplied. This cannot
# measure the new model behavior and never enables the provider budget helper.
require_relative "support"
raise "Preflight requires test environment" unless Rails.env.test?
PhysicalConfirmation.empty_database!
root = PhysicalConfirmation::ROOT
original = PhysicalConfirmation::ORIGINAL
before = JSON.parse(original.join("physical-after.json").read)
checking = ENV["PHYSICAL_GATE_CHECK"] == "1"
reference = checking ? JSON.parse(root.join("requests.json").read).fetch("samples") : before.fetch("results")
PhysicalConfirmation.gate = PhysicalConfirmation::Gate.new(reference, capture: !checking)

module FinalPhysicalOffline
  Response = Data.define(:content)
  class << self
    attr_accessor :remaining
  end

  module Conversation
    def ask(prompt, **)
      row = FinalPhysicalOffline.remaining.shift or raise PhysicalConfirmation::Halt, "Unrecorded provider request"
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

FinalPhysicalOffline.remaining = before.fetch("results").flat_map { |row| row.fetch("calls") }.dup
RubyLLM.config.openrouter_api_key = "offline-recorded-answer"
RubyLLM.config.openrouter_api_base = "http://127.0.0.1:1"
BaseAgent.define_singleton_method(:default_model_options) do
  [ { model: ReviewEvalBudget::MODEL, provider: :openrouter, assume_model_exists: false } ]
end
ReviewEvalBudget.define_singleton_method(:install!) { }
Chat.prepend(FinalPhysicalOffline::Conversation)
PhysicalConfirmation.install!
ENV["EVAL_BUDGET_HELPER"] = PhysicalConfirmation::HELPER.to_s
ENV["EVAL_PREFLIGHT"] = "0"
ENV["EVAL_SOURCE_SHA"] = "offline-final-confirmation"
ENV["EVAL_ARM"] = PhysicalConfirmation::LABEL
ENV["REPS"] = "4"
ENV["OUT"] = ENV.fetch("PHYSICAL_REPLAY_OUT")
load original.join("evaluate.rb")
raise "Unplayed baseline receipts" unless FinalPhysicalOffline.remaining.empty?
replay = JSON.parse(File.read(ENV.fetch("OUT")))
fields = %w[before after narration refusal resolved_action fallback interactions error]
replay.fetch("results").zip(before.fetch("results")).each do |actual, old|
  raise "Replay changed engine outcome" unless actual.slice(*fields) == old.slice(*fields)
end
requests = PhysicalConfirmation.gate.requests.dup
samples = before.fetch("results").map do |row|
  row.slice("case", "rep", "line", "before").merge("calls" => requests.shift(row.fetch("calls").length))
end
document = { endpoint: "https://openrouter.ai/api/v1/chat/completions", model: ReviewEvalBudget::MODEL,
  provider: ReviewEvalBudget::PROVIDER, repetitions: 4, turn_count: 28, max_calls: 60,
  content: "Fixed fictional Cal/Maren market fixtures. Decision requests are exact; dependent narrator requests must use the fresh fixture answer and engine receipt through frozen builders.",
  samples: samples }
path = root.join("requests.json")
if checking
  raise "Replayed allowlist changed" unless JSON.parse(path.read) == PhysicalConfirmation.json(document)
else
  raise "Refusing to overwrite a prepared allowlist" if path.exist?
  File.write(path, JSON.pretty_generate(document) + "\n")
end
calls = before.fetch("results").flat_map { |row| row.fetch("calls") }
source = PhysicalConfirmation.source
ledger = JSON.parse(File.read(FinalPhysicalConfirmation::LEDGER))
reservations = samples.flat_map { |row| row.fetch("calls") }.map do |request|
  bytes = JSON.generate(request.except("purpose")).bytesize
  (bytes + ReviewEvalBudget::MESSAGE_OVERHEAD_TOKENS) * ReviewEvalBudget::INPUT_RATE +
    ReviewEvalBudget::MAX_OUTPUT_TOKENS * ReviewEvalBudget::OUTPUT_RATE
end
manifest = { source_commit: `git rev-parse HEAD`.strip, source: source,
  source_sha256: Digest::SHA256.hexdigest(JSON.generate(source)), requests_sha256: Digest::SHA256.file(path).hexdigest,
  baselines: %w[physical-before.json physical-after.json manual-audit.json comparison.json].to_h { |file| [ file, Digest::SHA256.file(original.join(file)).hexdigest ] },
  isolated_database: PhysicalConfirmation::DATABASE, model: ReviewEvalBudget::MODEL, provider: ReviewEvalBudget::PROVIDER,
  replayed_turns: 28, replayed_requests: 60, changed_requests: { classifier_instructions_only: 28 },
  request_guard_mode: checking ? "live pre-send guard with stored answers returned offline" : "capture against original receipts",
  engine_states_and_outcomes_match: true, prior_actual_registry_usd: calls.sum { |call| call.fetch("registry_cost_usd") },
  planning_estimate_usd: 0.04, largest_inspected_reservation_usd: reservations.max.fdiv(1_000_000),
  shared_ceiling_usd: ReviewEvalBudget::LIMIT_MICROS.fdiv(1_000_000),
  shared_accounted_usd_at_preflight: ledger.fetch("entries").sum { |row| row.fetch("accounted_micros") }.fdiv(1_000_000),
  pricing: calls.first.fetch("registry_rates"), budget_helper: PhysicalConfirmation::HELPER.relative_path_from(Rails.root).to_s,
  authorization: "Offline preparation only; no provider calls or budget reservations made." }
File.write(root.join("preflight.json"), JSON.pretty_generate(manifest) + "\n")
puts JSON.generate(manifest.except(:source, :baselines, :pricing))
