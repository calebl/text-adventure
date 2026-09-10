# Fixture repair only: the first pending_toll used a room hazard on an edge.
# Preserve its readings and billing, then replace only that case's baseline.
# Run with the same DATABASE_URL, EVAL_LIVE and EVAL_BUDGET_FILE as the first buy.
file = Eval::Arrival::BASELINE.join(Eval::Arrival::RESULTS)
data = JSON.parse(file.read)
raise "repair already recorded" if data["superseded_rows"]
kase = Eval::Arrival.cases.find { |k| k.fetch("id") == "pending_toll" }
reps = Eval::Noise::MIN_RUNS
price = Eval::Cost.price(Eval::Arrival.model)
raise "unpriced" unless price.input_per_million.positive? && price.output_per_million.positive?
tokens = Eval::Prompt::PER_CALL.fetch("arrival")
estimate = { reason: "Correct edge hazard fixture", calls: reps, model: Eval::Arrival.model,
  estimated_usd: price.of(tokens[:input] * reps, tokens[:output] * reps) }
puts JSON.pretty_generate(estimate)
Rails.root.join("doc/evidence/ta-bench-arrival-branches/repair-estimate.json").write(JSON.pretty_generate(estimate) + "\n")
Eval::Arrival::Budget.assert_isolated_database!
Eval::Arrival::Budget.install!
data["superseded_rows"] = data.fetch("rows").select { |r| r.fetch("id") == kase.fetch("id") }
data["repair_estimate"] = estimate
(1..reps).each do |rep|
  Eval::Arrival::Budget.label = "pending_toll:#{rep}:corrected-source"
  Eval::Arrival::Budget.calls = []
  row = Eval::Arrival::Bench.new.read(kase, rep: rep)
  row["calls"] = Eval::Arrival::Budget.calls
  index = data.fetch("rows").index { |r| r.fetch("id") == kase.fetch("id") && r.fetch("rep") == rep }
  data.fetch("rows")[index] = row
  data["budget"] = Eval::Arrival::Budget.ledger.snapshot
  file.write(JSON.pretty_generate(data) + "\n")
  puts "pending_toll:#{rep}: #{row['error'] || 'recorded'}"
  $stdout.flush
end
