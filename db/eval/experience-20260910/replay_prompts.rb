require "json"
require_relative "fixtures"
require Rails.root.join("db/eval/adversarial-20260909/eval-budget-streaming-v2")
ReviewEvalBudget.assert_isolated_database!
raise "Replay requires the test environment" unless Rails.env.test?
# The fixtures restore historical Chat rows; RubyLLM validates their provider
# configuration even though nothing is sent. Use an inert configuration and
# block the provider boundary so replay works without a real API key.
RubyLLM.config.openrouter_api_key = "offline-request-replay"
RubyLLM.config.openrouter_api_base = "http://127.0.0.1:1"
Chat.define_method(:ask) { |*| raise ReviewEvalBudget::Halt, "Prompt replay attempted a provider call" }

source = JSON.parse(File.read(File.join(__dir__, "experience-after.json")))
# The revised candidate used a fresh prepared and seeded database.
checked = 0
source.fetch("results").each do |row|
  fixture = ExperienceFixtures.build(row.fetch("case"))
  game, npc = fixture.values_at(:game, :npc)
  agent = InteractionAgent.new(npc, playthrough: game)
  actual_prompt = agent.character_prompt(row.fetch("line")).gsub(/^give:\d+(?=: Give )/, "give:<item>")
  expected_prompt = row.fetch("fixture").fetch("prompt").gsub(/^give:\d+(?=: Give )/, "give:<item>")
  raise "Changed prompt #{row.fetch('case')}:#{row.fetch('rep')}" unless actual_prompt == expected_prompt
  raise "Changed instructions" unless agent.character_instructions == row.fetch("fixture").fetch("instructions")
  checked += 1
end
puts "#{checked} character requests match the measured candidate after normalizing item IDs. No model calls."
