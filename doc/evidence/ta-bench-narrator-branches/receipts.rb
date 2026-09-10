# Recompute token-priced spend, including the excluded warm-up, from kept rows.
# These are the loaded registry prices recorded before the purchase, not a
# claim to reproduce a provider invoice's caching adjustments.
require "json"
require "pathname"
root = Pathname.new(__dir__).join("../../..").expand_path
estimate = JSON.parse(Pathname.new(__dir__).join("estimate.json").read)
set = root.join("db/eval/prompt-branches-2026-09-10")
document = JSON.parse(set.join("prompt.json").read)
rows = document.fetch("passes").flat_map { |pass| pass.fetch("readings") }
rows += document.fetch("warmups").map { |warmup| warmup.fetch("reading") }
input = rows.sum { |row| row.fetch("input_tokens") }
output = rows.sum { |row| row.fetch("output_tokens") }
cost = (input * estimate.fetch("input_per_million") + output * estimate.fetch("output_per_million")) / 1_000_000.0
raise "authorization exceeded" if cost > estimate.fetch("authorized_usd")
puts JSON.pretty_generate({ model: estimate.fetch("model"), calls: rows.sum { |row| row.fetch("calls") },
                            input_tokens: input, output_tokens: output,
                            input_per_million: estimate.fetch("input_per_million"),
                            output_per_million: estimate.fetch("output_per_million"),
                            estimate_usd: estimate.fetch("estimate_usd") + estimate.fetch("warmup_estimate_usd"),
                            actual_usd: cost, includes_warmup: true, authorized_usd: estimate.fetch("authorized_usd") })
