# Replay the purchased candidate through the current turn engine. Each emitted
# system/user/schema request must match its stored receipt before the saved
# answer is returned. This proves integration preserved the measured requests
# and state; it is not a fresh model measurement. Use a fresh seeded test DB.
require "json"
require "digest"
require_relative "fixtures"
require Rails.root.join("db/eval/adversarial-20260909/eval-budget-streaming-v2")

module PhysicalReplay
  class Mismatch < Exception; end
  Response = Data.define(:content)

  class << self
    attr_accessor :calls, :checked
  end

  module Agent
    def ask(prompt, **options, &block)
      expected = PhysicalReplay.calls.first
      raise Mismatch, "Unmeasured request" unless expected

      actual = { "purpose" => purpose, "prompt" => prompt,
                 "instructions" => instructions, "schema" => schema&.new&.to_json_schema }
      actual = JSON.parse(JSON.generate(actual))
      actual.each do |key, value|
        raise Mismatch, "Changed #{purpose} #{key}" unless expected.fetch(key) == value
      end
      PhysicalReplay.checked += 1
      super
    end
  end

  module Conversation
    def ask(prompt, **)
      receipt = PhysicalReplay.calls.shift
      raise Mismatch, "Unmeasured provider call" unless receipt

      answer = receipt.fetch("raw_answer")
      messages.create!(role: "user", content: prompt)
      if answer.is_a?(Hash) || answer.is_a?(Array)
        messages.create!(role: "assistant", content_raw: answer)
      else
        messages.create!(role: "assistant", content: answer)
      end
      response = Response.new(content: answer)
      yield response if block_given?
      response
    end
  end
end

ReviewEvalBudget.assert_isolated_database!
raise "Replay requires the test environment" unless Rails.env.test?
RubyLLM.config.openrouter_api_key = "offline-recorded-answer"
RubyLLM.config.openrouter_api_base = "http://127.0.0.1:1"
BaseAgent.define_singleton_method(:default_model_options) do
  [ { model: ReviewEvalBudget::MODEL, provider: :openrouter, assume_model_exists: false } ]
end
BaseAgent.prepend(PhysicalReplay::Agent)
Chat.prepend(PhysicalReplay::Conversation)
PhysicalReplay.checked = 0
source = JSON.parse(File.read(File.join(__dir__, "physical-after.json")))

source.fetch("results").each do |row|
  fixture = PhysicalFixtures.build(row.fetch("case"))
  before = JSON.parse(JSON.generate(PhysicalFixtures.state(fixture)))
  raise PhysicalReplay::Mismatch, "Changed starting state #{row['case']}" unless before == row.fetch("before")

  PhysicalReplay.calls = row.fetch("calls").dup
  outcome = Playthrough::Turn.new(fixture.fetch(:game)).play(
    row.fetch("line"), request_token: "physical-#{row.fetch('case')}-#{row.fetch('rep') - 1}"
  )
  raise PhysicalReplay::Mismatch, "Unplayed receipts" unless PhysicalReplay.calls.empty?
  after = JSON.parse(JSON.generate(PhysicalFixtures.state(fixture)))
  raise PhysicalReplay::Mismatch, "Changed final state #{row['case']}" unless after == row.fetch("after")
  interactions = Interaction.where(character: fixture.fetch(:npc)).order(:id).map do |interaction|
    interaction.attributes.slice("action", "inner_resolution", "engine_action", "action_status", "action_fact")
  end
  raise PhysicalReplay::Mismatch, "Changed NPC record #{row['case']}" unless interactions == row.fetch("interactions")

  actual = if outcome.is_a?(Scene)
    { "narration" => outcome.description, "resolved_action" => outcome.resolved_action, "fallback" => outcome.engine_fallback? }
  else
    { "refusal" => outcome.text }
  end
  actual.each do |key, value|
    raise PhysicalReplay::Mismatch, "Changed #{key} #{row['case']}" unless value == row.fetch(key)
  end
end
puts "#{source.fetch('results').size} turns, #{PhysicalReplay.checked} exact system/user/schema requests and their final states replayed. No model calls."
