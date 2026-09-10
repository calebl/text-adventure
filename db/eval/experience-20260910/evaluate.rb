require "json"
require "digest"
require_relative "fixtures"
require ENV.fetch("EVAL_BUDGET_HELPER")

$stdout.sync = true
ReviewEvalBudget.assert_isolated_database!
ReviewEvalBudget.install!
specs = JSON.parse(File.read(File.join(__dir__, "cases.json")))
reps = Integer(ENV.fetch("REPS", "4"))
raise "At least four repetitions are required" if reps < 4
output = ENV.fetch("OUT")
raise "Refusing to overwrite an existing evaluation" if File.exist?(output)
source = ENV.fetch("EVAL_SOURCE_SHA")
metadata = { model: ReviewEvalBudget::MODEL, provider: ReviewEvalBudget::PROVIDER,
             source: source, reps: reps, preflight: false,
             corpus: Digest::SHA256.hexdigest(JSON.generate(specs)),
             fixtures_sha256: Digest::SHA256.file(File.join(__dir__, "fixtures.rb")).hexdigest,
             results: [] }
reps.times do |rep|
  specs.each do |spec|
    fixture = ExperienceFixtures.build(spec.fetch("id"))
    game, npc, key = fixture.values_at(:game, :npc, :key)
    raise "Fixture left a SQL transaction open" if ActiveRecord::Base.connection.transaction_open?
    agent = InteractionAgent.new(npc, playthrough: game)
    ReviewEvalBudget.calls = []
    ReviewEvalBudget.label = "experience:#{ENV.fetch('EVAL_ARM')}:#{spec.fetch('id')}:#{rep + 1}"
    before = { hp: game.vitals_for(npc).hp, max_hp: npc.max_hp,
               carried: game.carried.pluck(:name), npc_items: game.items_held_by(npc).pluck(:name),
               prompt: agent.character_prompt(spec.fetch("line")),
               instructions: agent.character_instructions,
               memories: Interaction.where(character: npc).order(:id).map do |row|
                 row.attributes.slice("user_input", "action", "inner_resolution", "action_fact")
               end }
    exchange = nil
    failure = nil
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      exchange = agent.ask(spec.fetch("line"))
    rescue StandardError, ReviewEvalBudget::Halt => error
      failure = error
    end
    effect = exchange&.effect
    metadata[:results] << { case: spec.fetch("id"), rep: rep + 1, line: spec.fetch("line"),
      fixture: before, reaction: exchange&.reaction, narration: exchange&.narration,
      action: effect&.action, status: effect&.status, fact: effect&.fact,
      fallback: exchange&.fallback?, key_held_by_npc: key.reload.character_id == npc.id,
      carries_key: game.carried.where(id: key.id).exists?, calls: ReviewEvalBudget.calls,
      error: failure&.class&.name, seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
    File.write(output, JSON.pretty_generate(metadata))
    puts "#{spec.fetch('id')} rep #{rep + 1}: #{effect&.action || failure&.class || 'no receipt'}"
    model_failure = failure.is_a?(BaseAgent::SchemaIgnoredError) || failure.is_a?(BaseAgent::UnusableResponseError)
    raise failure if failure && !model_failure
  end
end
