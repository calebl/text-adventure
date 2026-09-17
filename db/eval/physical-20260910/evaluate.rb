require "json"
require "digest"
require_relative "fixtures"
require ENV.fetch("EVAL_BUDGET_HELPER")

$stdout.sync = true
ReviewEvalBudget.assert_isolated_database!
preflight = ENV["EVAL_PREFLIGHT"] == "1"
ReviewEvalBudget.install! unless preflight
specs = JSON.parse(File.read(File.join(__dir__, "cases.json")))
output = ENV.fetch("OUT")
raise "Refusing to overwrite a saved result" if File.exist?(output)
reps = preflight ? 1 : Integer(ENV.fetch("REPS", "4"))
raise "Four repetitions required" if !preflight && reps < 4
metadata = { model: ReviewEvalBudget::MODEL, provider: ReviewEvalBudget::PROVIDER, preflight: preflight,
  reps: reps, source: ENV.fetch("EVAL_SOURCE_SHA"), corpus: Digest::SHA256.hexdigest(JSON.generate(specs)),
  fixtures_sha256: Digest::SHA256.file(File.join(__dir__, "fixtures.rb")).hexdigest, results: [] }
reps.times do |rep|
  specs.each do |spec|
    fixture = PhysicalFixtures.build(spec.fetch("id"))
    game = fixture.fetch(:game)
    before = PhysicalFixtures.state(fixture)
    classifier = Playthrough::Classifier.new(game)
    inputs = { instructions: Playthrough::Classifier::INSTRUCTIONS,
      prompt: classifier.command_prompt(spec.fetch("line"), classifier.exits_here, classifier.characters_here,
        classifier.items_here, classifier.items_carried) }
    outcome = failure = nil
    ReviewEvalBudget.calls = []
    ReviewEvalBudget.label = "physical:#{ENV.fetch('EVAL_ARM')}:#{spec.fetch('id')}:#{rep + 1}"
    begin
      outcome = Playthrough::Turn.new(game).play(spec.fetch("line"), request_token: "physical-#{spec.fetch('id')}-#{rep}") unless preflight
    rescue StandardError, ReviewEvalBudget::Halt => error
      failure = error
    end
    metadata[:results] << { case: spec.fetch("id"), rep: rep + 1, line: spec.fetch("line"), before: before,
      inputs: inputs, after: PhysicalFixtures.state(fixture),
      narration: outcome.is_a?(Scene) ? outcome.description : nil,
      refusal: outcome.is_a?(Playthrough::Refusal) ? outcome.text : nil,
      resolved_action: outcome.is_a?(Scene) ? outcome.resolved_action : nil,
      fallback: outcome.is_a?(Scene) && outcome.engine_fallback?,
      interactions: Interaction.where(character: fixture.fetch(:npc)).order(:id).map do |row|
        row.attributes.slice("action", "inner_resolution", "engine_action", "action_status", "action_fact")
      end,
      calls: ReviewEvalBudget.calls, error: failure&.class&.name }
    File.write(output, JSON.pretty_generate(metadata))
    puts "#{spec.fetch('id')} rep #{rep + 1}: #{outcome&.class || (preflight ? 'preflight' : failure&.class)}"
    raise failure if failure
  end
end
