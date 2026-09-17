require 'json'
require 'digest'
RubyLLM.models.load_from_json!
Model.save_to_database
# A replay must never reach a provider.
Chat.prepend(Module.new do
  def ask(*) = raise('Offline preflight attempted a provider call')
end)
root = Rails.root.join('db/eval/physical-dialogue-20260910')
before_path = Rails.root.join('db/eval/dialogue-2026-09-10/dialogue.json')
before = Eval::Dialogue::Result.load(before_path.dirname)
before.validate_complete!
raise 'Need four stored before repetitions' if before.data.fetch('reps') < Eval::Noise::MIN_RUNS
raise 'Mismatched corpus or model' unless before.data.fetch('corpus_digest') == Eval::Dialogue.digest && before.data.fetch('model') == Eval::Dialogue.model
changes = before.rows.map do |row|
  now = Eval::Dialogue::Version.rebuild(row)
  { id: row.fetch('id'), rep: row.fetch('rep'), changed_passes: row.fetch('requests').zip(now.fetch('requests')).each_with_index.filter_map { |(a, b), i| i+1 unless a==b }, facts_unchanged: row.fetch('facts')==now.fetch('facts') }
end
manifest = { before_sha256: Digest::SHA256.file(before_path).hexdigest, corpus_sha256: Eval::Dialogue.digest,
  source_commit: `git rev-parse HEAD`.strip, model: Eval::Dialogue.model, estimate: Eval::Dialogue.estimate(reps: 4),
  request_samples_sha256: Digest::SHA256.file(root.join('request-samples.json')).hexdigest,
  payload_gate_sha256: Digest::SHA256.file(root.join('payload_gate.rb')).hexdigest,
  source: %w[app/agents/InteractionAgent.rb app/models/playthrough/memory.rb app/models/playthrough/moment.rb app/models/playthrough/npc_action.rb lib/eval/dialogue.rb lib/eval/dialogue/bench.rb lib/eval/dialogue/stage.rb lib/eval/dialogue/result.rb lib/eval/dialogue/version.rb test/fixtures/files/dialogue_corpus.json db/eval/adversarial-20260909/eval-budget-streaming-v2.rb].to_h { |name| [ name, Digest::SHA256.file(Rails.root.join(name)).hexdigest ] }, changes: changes }
File.write(root.join('preflight.json'), JSON.pretty_generate(manifest)+"\n")
File.write(root.join('before-board.json'), JSON.pretty_generate(before.board)+"\n")
puts JSON.generate(readings: changes.size, changed_passes: changes.group_by { |x| x[:changed_passes] }.transform_values(&:size), facts_unchanged: changes.all? { |x| x[:facts_unchanged] }, estimate: manifest[:estimate])
