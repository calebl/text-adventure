# Authorized fixed-fiction dialogue follow-up. Run with an isolated DATABASE_URL,
# EVAL_LIVE=1 and the existing shared EVAL_BUDGET_FILE; never Dialogue::Budget.
# Every completed reading is atomically retained. A resumed invocation skips
# only completed pairs; provider/guard errors stop immediately and are retained.
require 'json'
require 'digest'
require Rails.root.join('db/eval/adversarial-20260909/eval-budget-streaming-v2')
require_relative 'payload_gate'

set_name = 'physical-dialogue-20260910'
root = Rails.root.join('db/eval', set_name)
file = root.join(Eval::Dialogue::RESULTS)
preflight = JSON.parse(root.join('preflight.json').read)
raise 'Inspected payload manifest changed' unless Digest::SHA256.file(root.join('request-samples.json')).hexdigest == preflight.fetch('request_samples_sha256')
raise 'Tested payload gate changed' unless Digest::SHA256.file(root.join('payload_gate.rb')).hexdigest == preflight.fetch('payload_gate_sha256')
raise 'Corpus changed after preflight' unless preflight.fetch('corpus_sha256') == Eval::Dialogue.digest
raise 'Model is not the approved single arm' unless Eval::Dialogue.model == ReviewEvalBudget::MODEL
raise 'Need exactly four repetitions for the matched set' unless ENV.fetch('REPS', '4').to_i == 4
preflight.fetch('source').each do |name, digest|
  raise "Source changed after preflight: #{name}" unless Digest::SHA256.file(Rails.root.join(name)).hexdigest == digest
end
ReviewEvalBudget.assert_isolated_database!
ReviewEvalBudget.install!
PhysicalDialoguePayload.install!
run_lock = File.open(Rails.root.join('tmp/physical-dialogue-20260910-run.lock'), File::RDWR | File::CREAT, 0o600)
raise 'This dialogue run is already active' unless run_lock.flock(File::LOCK_EX | File::LOCK_NB)

def write_atomically(file, data)
  temporary = "#{file}.writing"
  File.write(temporary, JSON.pretty_generate(data) + "\n")
  File.rename(temporary, file)
end

def task_budget(set_name)
  snapshot = ReviewEvalBudget.ledger.snapshot
  scoped = snapshot.fetch('entries').select { |entry| entry.fetch('label').start_with?("#{set_name}:") }
  snapshot.merge('entries' => scoped, 'entries_scope' => "Labels starting #{set_name}:",
    'shared_accounted_micros' => snapshot.fetch('entries').sum { |entry| entry.fetch('accounted_micros') },
    'task_accounted_micros' => scoped.sum { |entry| entry.fetch('accounted_micros') })
end

data = if file.exist?
  JSON.parse(file.read).tap do |kept|
    raise 'Existing set has another corpus/model/repetition count' unless kept.values_at('corpus_digest', 'model', 'reps') == [ Eval::Dialogue.digest, Eval::Dialogue.model, 4 ]
    raise 'Existing set has duplicated readings' unless kept.fetch('rows').map { |row| row.values_at('id', 'rep') }.uniq.size == kept.fetch('rows').size
  end
else
  { 'model' => Eval::Dialogue.model, 'reps' => 4, 'corpus_digest' => Eval::Dialogue.digest,
    'recorded_at' => Time.now.utc.iso8601, 'estimate' => Eval::Dialogue.estimate(reps: 4),
    'source_commit' => preflight.fetch('source_commit'), 'before_sha256' => preflight.fetch('before_sha256'),
    'budget_helper_sha256' => preflight.fetch('source').fetch('db/eval/adversarial-20260909/eval-budget-streaming-v2.rb'),
    'budget_scope' => 'The authorized shared $4 ledger retains all prior charges; this document includes only this task label subset plus the shared total.',
    'rows' => [], 'interrupted_attempts' => [] }
end
remaining = (1..4).flat_map { |rep| Eval::Dialogue.cases.map { |kase| [ kase.fetch('id'), rep ] } } - data.fetch('rows').map { |row| row.values_at('id', 'rep') }
prior_entries = task_budget(set_name).fetch('entries')
attempted = prior_entries.map { |entry| parts = entry.fetch('label').split(':'); [ parts[1], Integer(parts[2]) ] }.uniq
PhysicalDialoguePayload.gate = PhysicalDialoguePayload::Gate.new(samples: JSON.parse(root.join('request-samples.json').read), allowed: remaining, attempted: attempted)
data['payload_gate_sha256'] = Digest::SHA256.file(root.join('payload_gate.rb')).hexdigest
write_atomically(file, data)
bench = Eval::Dialogue::Bench.new
(1..4).each do |rep|
  Eval::Dialogue.cases.each do |kase|
    next if data.fetch('rows').any? { |row| row.values_at('id', 'rep') == [ kase.fetch('id'), rep ] }
    ReviewEvalBudget.label = "#{set_name}:#{kase.fetch('id')}:#{rep}"
    ReviewEvalBudget.calls = []
    PhysicalDialoguePayload.gate.start!(kase.fetch('id'), rep)
    begin
      row = bench.read(kase, rep: rep)
      calls = JSON.parse(JSON.generate(ReviewEvalBudget.calls))
      # The shared helper predates full history receipts. Bench captured these
      # exact histories immediately before the same BaseAgent calls; do not
      # infer or normalize any request bytes after the response.
      calls.zip(row.fetch('requests')).each do |call, request|
        raise 'A call has no corresponding captured request' unless request
        raise 'Call and request disagree' unless call.values_at('instructions', 'prompt', 'schema') == request.values_at('system', 'user', 'schema')
        call['history'] = request.fetch('history')
      end
      row['calls'] = calls
      data.fetch('rows') << row
      data['budget'] = task_budget(set_name)
      write_atomically(file, data)
      puts "#{kase.fetch('id')}:#{rep} #{row['error'] || 'recorded'}"
      $stdout.flush
      raise "Recorded dialogue failure: #{kase.fetch('id')}:#{rep}" if row['error'] || row['fallback'] || calls.any? { |call| call['error'] }
    rescue Exception => error
      unless data.fetch('rows').any? { |row| row.values_at('id', 'rep') == [ kase.fetch('id'), rep ] }
        data.fetch('interrupted_attempts') << { 'id' => kase.fetch('id'), 'rep' => rep, 'error' => error.class.name,
          'message' => error.message, 'calls' => JSON.parse(JSON.generate(ReviewEvalBudget.calls)) }
      end
      data['budget'] = task_budget(set_name)
      write_atomically(file, data)
      raise
    end
  end
end
Eval::Dialogue::Result.new(data).validate_complete!
puts JSON.generate(readings: data.fetch('rows').size, calls: data.fetch('rows').sum { |row| row.fetch('calls').size },
  task_accounted_usd: data.fetch('budget').fetch('task_accounted_micros').fdiv(1_000_000),
  shared_accounted_usd: data.fetch('budget').fetch('shared_accounted_micros').fdiv(1_000_000))
