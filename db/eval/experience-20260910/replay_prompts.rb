require "json"
require_relative "fixtures"
require Rails.root.join("db/eval/adversarial-20260909/eval-budget-streaming-v2")
ReviewEvalBudget.assert_isolated_database!

source = JSON.parse(File.read(File.join(__dir__, "experience-after.json")))
# The revised candidate used a fresh prepared and seeded database.
checked = 0
source.fetch("results").each do |row|
  fixture = ExperienceFixtures.build(row.fetch("case"))
  game, npc = fixture.values_at(:game, :npc)
  agent = InteractionAgent.new(npc, playthrough: game)
  raise "Changed prompt #{row.fetch('case')}:#{row.fetch('rep')}" unless agent.character_prompt(row.fetch("line")) == row.fetch("fixture").fetch("prompt")
  raise "Changed instructions" unless agent.character_instructions == row.fetch("fixture").fetch("instructions")
  checked += 1
end
puts "#{checked} character requests match the measured candidate byte for byte. No model calls."
