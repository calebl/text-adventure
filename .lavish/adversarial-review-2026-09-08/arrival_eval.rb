# Fixed R03 arrival cases, runnable against the original HEAD and the fix.
# Use an isolated database with its schema and model registry prepared first:
#   ARRIVAL_EVAL_OUTPUT=/tmp/arrival-before.json REPS=4 bin/rails runner PATH
# Every repetition rolls back its world; prompts and answers survive in JSON.
# No existing corpus is changed. All calls go through BaseAgent on one model.
require "factory_bot_rails"
require "digest"
require ENV.fetch("EVAL_BUDGET_HELPER", File.join(__dir__, "pending/eval_budget.rb"))
ReviewEvalBudget.assert_isolated_database!

FactoryBot.find_definitions if FactoryBot.factories.none?
reps = Integer(ENV.fetch("REPS", "4"))
raise "At least four repetitions are required" if reps < 4

cases = %w[dead_resident carried_key crossing_harm]
rows = []
model = ReviewEvalBudget::MODEL
preflight = ENV["EVAL_PREFLIGHT"] == "1"
ReviewEvalBudget.install! unless preflight
output = ENV.fetch("ARRIVAL_EVAL_OUTPUT")
metadata = { model: model, provider: ReviewEvalBudget::PROVIDER, reps: reps, cases: cases,
             preflight: preflight, ceiling_usd: 3,
             rate_bounds_usd_per_million: { input: ReviewEvalBudget::INPUT_RATE, output: ReviewEvalBudget::OUTPUT_RATE },
             output_token_cap: ReviewEvalBudget::MAX_OUTPUT_TOKENS,
             rate_note: "Conservative reservation assumptions; live calls first check seeded model metadata. Provider charges are captured separately." }

cases.each do |case_id|
  reps.times do |rep|
    ActiveRecord::Base.transaction(requires_new: true) do
      story = FactoryBot.create(:story, title: "The Drowned Ledger", genre: "mystery",
                                summary: "You are tracing a missing ship's account through the flooded counting house.",
                                start_time: Time.utc(2026, 1, 1, 12))
      hero = FactoryBot.create(:character, :protagonist, story: story, fullname: "Iri Calder", nickname: "Iri",
                               age: 25, sex: "female", level: 3)
      origin = FactoryBot.create(:location, story: story, name: "Market", description: "Rain falls between shuttered stalls.")
      destination = FactoryBot.create(:location, story: story, name: "Counting House",
                                      description: "Maren Vosk waits beside a brass key on the desk. Water laps at the lowest stair.",
                                      lore: "This counting house kept the harbour's manifests.")
      FactoryBot.create(:location_connection, location: origin, connected_location: destination,
                        distance: "a short walk", travel_method: "walking")
      FactoryBot.create(:location_connection, location: destination, connected_location: origin,
                        distance: "a short walk", travel_method: "walking")
      opening = FactoryBot.create(:scene, :opening, story: story, location: origin,
                                   story_timestamp: story.start_time,
                                   description: "You leave the market and approach the counting house.",
                                   summary: "You leave the market for the counting house.")
      game = FactoryBot.create(:playthrough, story: story, character: hero,
                                current_location: origin, current_scene: opening)
      person = FactoryBot.create(:character, story: story, location: destination,
                                  fullname: "Maren Vosk", nickname: "Maren", age: 40, sex: "female")
      key = FactoryBot.create(:item, :lying, location: destination, name: "brass key")
      Playthrough::Snapshot.new(game).of_the_room!(destination)
      turn = Playthrough::Turn.new(game)

      expected = case case_id
      when "dead_resident"
        turn.harm!(person, person.max_hp)
        { dead: [ person.fullname ], living: [ hero.fullname ], floor: [ key.name ], carried: [] }
      when "carried_key"
        turn.carry!(game.items.find_by!(template: key))
        { living: [ hero.fullname, person.fullname ], floor: [], carried: [ key.name ] }
      when "crossing_harm"
        turn.harm!(hero, 3)
        FactoryBot.create(:playthrough_toll, playthrough: game, location: destination,
                            character: hero, damage: 3, hp_after: game.condition.hp,
                            story_timestamp: story.start_time)
        { living: [ hero.fullname, person.fullname ], damage: 3, hp: game.condition.hp,
          source: "Counting House", hazard: "flooded", saved: false }
      end

      generator = Scene::Generator.new(destination, previous_scene: opening, playthrough: game)
      agent = generator.agent.with_model(model: model, provider: :openrouter)
      ReviewEvalBudget.calls = []
      ReviewEvalBudget.label = "arrival:#{case_id}:#{rep + 1}"
      captured = []
      agent.define_singleton_method(:ask) do |prompt, **options, &block|
        captured << prompt
        super(prompt, **options, &block)
      end
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      failure = nil
      begin
        scene = generator.generate! unless preflight
        if preflight
          captured << generator.arrival_prompt(destination.last_protagonist_visit.present?,
                                              destination.time_since_last_visit(generator.story_timestamp),
                                              generator.characters_present)
        end
        rows << { case: case_id, rep: rep + 1, expected: expected,
                  instructions: generator.system_prompt, prompt: captured.last,
                  prompt_digest: Digest::SHA256.hexdigest(captured.last),
                  description: scene&.description, summary: scene&.summary, calls: ReviewEvalBudget.calls,
                  elapsed: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
      rescue StandardError, ReviewEvalBudget::Halt => error
        failure = error
        rows << { case: case_id, rep: rep + 1, expected: expected, prompt: captured.last,
                  error: error.class.name, message: error.message, calls: ReviewEvalBudget.calls }
      end
      File.write(output, JSON.pretty_generate({ **metadata, rows: rows }))
      puts "#{case_id} repetition #{rep + 1}: #{rows.last[:error] || "complete"}"
      raise failure if failure.is_a?(ReviewEvalBudget::Halt)
      raise ActiveRecord::Rollback
    end
  end
end
