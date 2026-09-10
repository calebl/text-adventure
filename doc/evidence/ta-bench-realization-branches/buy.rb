# Run with bin/rails runner. This is a single purchase, including a separately
# receipted warm-up; rerunning it requires a new spend decision.
require "zlib"
root = Rails.root.join("doc/evidence/ta-bench-realization-branches")
name = "branches-to-corpus-after"
kept = Eval.kept_root.join(name)
raise "set already exists" if kept.exist?
raise "reading journal already exists" if root.join("readings.jsonl").exist?
previous = JSON.parse(File.read(root.join("failed-export-receipts.json")))
previous_spend = previous.fetch("actual")
# Resolve lazily loaded measurement classes before the first paid call.
Eval::Realization::Result
Eval::Realization::BranchRequests.offline
model = "mistralai/mistral-medium-3.1"
arm = Eval::Classifier::Arm.parse(model)
price = arm.price
raise "unpriced registry" unless price.input_per_million.positive? && price.output_per_million.positive?
Eval::Realization.corpus.validate!
estimate = Eval::Realization.estimate(cases: Eval::Realization.corpus.cases, reps: Eval::Noise::MIN_RUNS, models: [ arm ])
raise "estimate over remaining authorization" if previous_spend + estimate > 2
# Reserve the registry's maximum input and output for both calls before a room.
# This intentionally overestimates interior and restored cases. No generation
# setting is changed to enforce the budget and failed rows are not retried.
registry = Model.find_by!(model_id: model)
reserve = 2 * price.of(registry.context_window, registry.max_output_tokens)
receipts = []
bench = Eval::Realization::Bench.new(arms: [ arm ], reps: Eval::Noise::MIN_RUNS)
original = bench.method(:build)
bench.define_singleton_method(:build) do |kase, standing, picked, rep|
  spent = receipts.sum { |row| row.fetch(:dollars) }
  raise "remaining authorization cannot cover worst-case room" if previous_spend + spent + reserve > 2
  reading = original.call(kase, standing, picked, rep)
  File.open(root.join("readings.jsonl"), "a") do |file|
    file.puts(JSON.generate(reading.to_h))
    file.flush
    file.fsync
  end
  receipts << { id: kase.id, rep: rep, warmup: rep.zero?, model: reading.answered_by,
                input_tokens: reading.input_tokens, output_tokens: reading.output_tokens,
                calls: reading.calls, dollars: price.of(reading.input_tokens.to_i, reading.output_tokens.to_i),
                error: reading.error }
  File.write(root.join("receipts.json"), JSON.pretty_generate({ estimate: estimate, price: price.to_h,
    previous_attempt: previous, current_actual: receipts.sum { |row| row.fetch(:dollars) },
    actual: previous_spend + receipts.sum { |row| row.fetch(:dollars) }, receipts: receipts }))
  puts "#{kase.id} rep=#{rep} calls=#{reading.calls} error=#{reading.error.inspect}"
  $stdout.flush
  reading
end
result = bench.run
result.write!(Eval.root.join(name), name: name)
result.summary.write!(kept, name: name)
Zlib::GzipWriter.open(kept.join("readings.json.gz")) { |file| file.write(JSON.generate(result.to_h)) }
requests = Eval::Realization::BranchRequests.offline
File.write(kept.join("requests.json"), JSON.pretty_generate({ request_identity: Eval::Realization::BranchRequests.identity(requests), requests: requests }))
FileUtils.cp(root.join("receipts.json"), kept.join("receipts.json"))
puts "ACTUAL including failed export #{previous_spend + receipts.sum { |row| row.fetch(:dollars) }}"
