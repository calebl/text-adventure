# Delegate to the existing sequential evaluator, with the shared approved
# spending guard and an additional receipt identifying factual fallback scenes.
# Does not change any corpus, scorer, provider request or engine branch.
require "json"
require "digest"
require ENV.fetch("EVAL_BUDGET_HELPER")

ReviewEvalBudget.assert_isolated_database!
unless ENV.fetch("EVAL_STORY") == "The Salt Assizes" && ENV.fetch("EVAL_TURNS") == "8" &&
    (1..4).cover?(Integer(ENV.fetch("EVAL_REP"))) && %w[before after].include?(ENV.fetch("CONFIRMATION_ARM"))
  raise "Confirmation is the unchanged first eight Salt Assizes turns, repetitions 1 through 4, before or after"
end
unless File.expand_path(ENV.fetch("EVAL_DB")) == File.expand_path(ActiveRecord::Base.connection_db_config.database)
  raise "DATABASE_URL and EVAL_DB must identify the same isolated run database"
end
unless ENV.fetch("OPENROUTER_MODEL") == ReviewEvalBudget::MODEL
  raise "The confirmation must use the approved model"
end

script = Eval::Script.for(ENV.fetch("EVAL_STORY")).first(8)
metadata = {
  arm: ENV.fetch("CONFIRMATION_ARM"), story: script.story, rep: Integer(ENV.fetch("EVAL_REP")),
  source_root: Rails.root.to_s, model: ReviewEvalBudget::MODEL, provider: ReviewEvalBudget::PROVIDER,
  script_sha256: Digest::SHA256.file(Eval::Script.path_for(script.story)).hexdigest,
  runner_sha256: Digest::SHA256.file(Rails.root.join("script/eval_run.rb")).hexdigest,
  budget_helper_sha256: Digest::SHA256.file(ENV.fetch("EVAL_BUDGET_HELPER")).hexdigest,
  turns: script.turns.map(&:to_h), scope: "Unchanged first eight turns; not a full-run or general NPC-realism verdict"
}
receipt_path = ENV.fetch("CONFIRMATION_RECEIPT")
if ENV["EVAL_PREFLIGHT"] == "1"
  File.write(receipt_path, JSON.pretty_generate(metadata.merge(preflight: true)))
  puts "Confirmation preflight: #{script.size} unchanged turns, no model calls"
  exit
end

ReviewEvalBudget.install!
ReviewEvalBudget.label = "confirmation:#{metadata.fetch(:arm)}:salt-assizes:r#{metadata.fetch(:rep)}"
failure = nil
begin
  load Rails.root.join("script/eval_run.rb")
rescue Exception => error
  failure = { class: error.class.name, message: error.message }
  raise
ensure
  manifest = JSON.parse(File.read(ENV.fetch("EVAL_OUT"))) if File.exist?(ENV.fetch("EVAL_OUT"))
  game_id = manifest&.fetch("playthrough_id", nil)
  scenes = game_id ? Playthrough.find(game_id).scene_chain.reject(&:is_opening?) : []
  fallback_scenes = scenes.select { |scene| scene.has_attribute?(:engine_fallback) && scene.engine_fallback? }
  sidecar = metadata.merge(
    failure: failure, calls: ReviewEvalBudget.calls, completed_manifest: !manifest.nil?,
    factual_fallback_scenes: fallback_scenes.map { |scene| { id: scene.id, action: scene.resolved_action, typed: scene.typed } },
    model_prose_comparison_eligible: failure.nil? && !manifest.nil? && fallback_scenes.empty?,
    note: "Standard scorer unchanged. Any factual fallback disqualifies a clean model-prose interpretation of its run."
  )
  File.write(receipt_path, JSON.pretty_generate(sidecar))
end
