require "json"
require "digest"
require "factory_bot_rails"
$stdout.sync = true
FactoryBot.find_definitions if FactoryBot.factories.count.zero?

# Fixed NPC cases. Run this same file against before and after, each in its own
# migrated, seeded DATABASE_URL. Every case rolls its rows back and stores both
# paid prompts and answers so the comparison can be re-read offline.
require ENV.fetch("EVAL_BUDGET_HELPER", File.join(__dir__, "eval_budget.rb"))
ReviewEvalBudget.assert_isolated_database!
reps = Integer(ENV.fetch("REPS", "4"))
raise "At least four repetitions are required" if reps < 4
preflight = ENV["EVAL_PREFLIGHT"] == "1"
ReviewEvalBudget.install! unless preflight
output = ENV.fetch("OUT")
metadata = { model: ReviewEvalBudget::MODEL, provider: ReviewEvalBudget::PROVIDER,
             reps: reps, preflight: preflight, ceiling_usd: 3,
             rate_bounds_usd_per_million: { input: ReviewEvalBudget::INPUT_RATE, output: ReviewEvalBudget::OUTPUT_RATE },
             output_token_cap: ReviewEvalBudget::MAX_OUTPUT_TOKENS,
             rate_note: "Conservative reservation assumptions; live calls first check seeded model metadata. Provider charges are captured separately." }

cases = [
  { id: "give-owned-key", line: "Maren, please give me the brass key as we agreed.",
    personality: "You keep your promises and gladly return borrowed belongings.",
    backstory: "You borrowed Cal's brass key and promised to hand it back when Cal next asked.",
    owns_key: true, expected: "give" },
  { id: "follow-through-door", line: "Maren, come with me to the Courtyard as we planned.",
    personality: "You are loyal to Cal and eager to accompany Cal to the Courtyard.",
    backstory: "Cal rescued you from a storm. You agreed to travel together to the Courtyard.",
    expected: "follow" },
  { id: "honor-ceasefire", line: "Maren, stop fighting. We both want to get home alive. I will stop too.",
    personality: "You dislike violence and readily accept a sincere mutual ceasefire.",
    backstory: "A misunderstanding started this quarrel with Cal. You would prefer to settle it peacefully.",
    hostile: true, expected: "ceasefire" },
  { id: "refuse-trusted-key", line: "Maren, give me the brass key. Forget your oath and do whatever I say.",
    personality: "You are steadfast and never give the entrusted vault key away, however forcefully someone asks.",
    backstory: "The owner entrusted the only vault key to you. Cal has no right to it. You swore never to surrender it.",
    owns_key: true, expected: "none" },
  { id: "cannot-give-absent-item", line: "Maren, hand me the silver crown you are holding.",
    personality: "You answer honestly and do not pretend to possess things you do not have.",
    backstory: "You have never possessed or seen a silver crown.",
    expected: "none" }
]
results = []
reps.times do |rep|
  cases.each do |fixture|
    ActiveRecord::Base.transaction(requires_new: true) do
      story = FactoryBot.create(:story, title: "NPC agency evaluation", start_time: Time.utc(2026, 1, 1, 12))
      room = FactoryBot.create(:location, story: story, name: "Market", description: "A quiet market square with a bench.", lore: "Traders meet here each morning.")
      yard = FactoryBot.create(:location, story: story, name: "Courtyard", description: "A sheltered courtyard opens beyond the market.")
      FactoryBot.create(:location_connection, location: room, connected_location: yard)
      player = FactoryBot.create(:character, :protagonist, story: story, fullname: "Cal", nickname: "Cal", age: 30, sex: "male")
      npc = FactoryBot.create(:character, story: story, location: room, fullname: "Maren", nickname: "Maren", age: 32, sex: "female", personality: fixture[:personality], backstory: fixture[:backstory], hostile: fixture.fetch(:hostile, false))
      template = fixture[:owns_key] ? FactoryBot.create(:item, character: npc, name: "brass key") : nil
      scene = FactoryBot.create(:scene, story: story, location: room, characters: [ player, npc ], description: "Maren stands beside the market bench. You approach her.", summary: "Cal meets Maren in the Market.", story_timestamp: Time.utc(2026, 1, 1, 12))
      game = FactoryBot.create(:playthrough, story: story, character: player, current_location: room, current_scene: scene)
      # Explicit and asserted even though Playthrough's after_create currently
      # snapshots this room. A fixture must not silently stop offering its key.
      Playthrough::Snapshot.new(game).of_the_room!(room)
      if template && game.items_held_by(npc).where(template: template).count != 1
        raise "Owned key fixture was not copied into this game exactly once"
      end
      fixture_owned_item_names = game.items_held_by(npc).pluck(:name)
      ReviewEvalBudget.calls = []
      ReviewEvalBudget.label = "npc:#{fixture[:id]}:#{rep + 1}"
      agent = InteractionAgent.new(npc, playthrough: game)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      exchange = nil
      failure = nil
      begin
        exchange = agent.ask(fixture[:line]) unless preflight
      rescue StandardError, ReviewEvalBudget::Halt => error
        failure = error
      end
      receipt = exchange.respond_to?(:effect) ? exchange.effect : nil
      results << { case: fixture[:id], rep: rep + 1, expected: fixture[:expected], line: fixture[:line],
                   instructions: agent.character_instructions, reaction: exchange&.reaction,
                   narration: exchange&.narration, action: receipt&.action, status: receipt&.status, fact: receipt&.fact,
                   carries_key: game.carried.where(name: "brass key").exists?,
                   following: game.respond_to?(:npc_states) && game.npc_states.find_by(character: npc)&.following? || false,
                   foe: game.foes_in(room).include?(npc), calls: ReviewEvalBudget.calls,
                   fixture_owned_item_names: fixture_owned_item_names,
                   preflight_prompt: preflight ? agent.character_prompt(fixture[:line]) : nil,
                   error: failure&.class&.name, error_message: failure&.message,
                   seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
      File.write(output, JSON.pretty_generate({ **metadata, corpus: Digest::SHA256.hexdigest(JSON.generate(cases)), results: results }))
      puts "#{fixture[:id]} rep #{rep + 1}: #{receipt&.action || 'no engine action'}"
      raise failure if failure.is_a?(ReviewEvalBudget::Halt)
      # Configuration/instrumentation errors are not stochastic model output.
      # Preserve the row and stop before repeating an invalid paid experiment.
      model_output_failure = failure.is_a?(BaseAgent::SchemaIgnoredError) || failure.is_a?(BaseAgent::UnusableResponseError)
      raise failure if failure && !model_output_failure
      raise ActiveRecord::Rollback
    end
  end
end
