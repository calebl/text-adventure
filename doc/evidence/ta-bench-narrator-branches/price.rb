# Run with bin/rails runner; models must have been loaded in this database first.
corpus = Eval::Prompt.corpus("branches")
arm = Eval::Classifier::Arm.parse("mistralai/mistral-medium-3.1")
price = arm.price
raise "registry has no price" unless price.of(1, 1).positive?
capture = Eval::Prompt::Branches.capture
reps = Eval::Noise::MIN_RUNS
estimate = Eval::Prompt.estimate(cases: corpus.cases, reps: reps, models: [ arm ])
warmup = Eval::Prompt.estimate(cases: [ corpus.cases.first ], reps: 1, models: [ arm ])
# Bytes as input tokens and a generous prose allowance, including warm-up.
input = capture.values.sum { |row| JSON.generate(row.fetch("request")).bytesize } * reps
input += JSON.generate(capture.fetch(corpus.cases.first.shape).fetch("request")).bytesize
conservative = price.of(input, (corpus.size * reps + 1) * 2_000)
raise "estimate exceeds authorization" if conservative > 2
puts JSON.pretty_generate({ model: arm.id, reps: reps, cases: corpus.size, calls_including_warmup: corpus.size * reps + 1,
                            input_per_million: price.input_per_million, output_per_million: price.output_per_million,
                            estimate_usd: estimate, warmup_estimate_usd: warmup,
                            conservative_allowance_usd: conservative, authorized_usd: 2,
                            request_identity: Eval::Prompt::Branches.identity(capture) })
