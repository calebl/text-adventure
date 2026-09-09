# Offline only: compare the stored standard scores without changing the scorer.
require "json"
require "stringio"

directory = Rails.root.join("db/eval/adversarial-20260909")
before = Eval::RunSet.load(directory.join("confirmation-before"))
after = Eval::RunSet.load(directory.join("confirmation-after"))
unless [ before, after ].all? { |set| set.runs.size == 4 && set.stories == [ "The Salt Assizes" ] && set.runs.all? { |run| run.turns == 8 } }
  raise "The confirmation requires four complete eight-turn runs per arm"
end
io = StringIO.new
comparison = Eval::Comparison.new(before, after, io: io)
comparison.print
File.write(directory.join("confirmation-comparison.txt"), io.string)

ledger = JSON.parse(File.read("/tmp/text-adventure-live-eval-20260909/budget.json"))
arms = %w[before after].to_h do |arm|
  set = arm == "before" ? before : after
  receipts = Dir.glob(directory.join("confirmation-#{arm}/receipts/*.json")).sort.map { |path| JSON.parse(File.read(path)) }
  entries = ledger.fetch("entries").select { |entry| entry.fetch("label").start_with?("confirmation:#{arm}:") }
  charges = entries.filter_map { |entry| entry.dig("receipt", "provider_cost_usd") }
  [ arm, {
    runs: set.runs.size, turns: set.runs.sum(&:turns), failed_turns: set.runs.sum { |run| run.failures.size },
    calls: entries.size, failed_calls: receipts.sum { |receipt| receipt.fetch("calls").count { |call| call["error"] } },
    factual_fallback_scenes: receipts.flat_map { |receipt| receipt.fetch("factual_fallback_scenes") },
    model_prose_comparison_eligible: receipts.all? { |receipt| receipt.fetch("model_prose_comparison_eligible") },
    accounted_usd: entries.sum { |entry| entry.fetch("accounted_micros") } / 1_000_000.0,
    provider_reported_usd: charges.sum, calls_without_provider_reported_charge: entries.size - charges.size,
    usage_priced_estimate_usd: set.cost.dollars,
    branch_divergences: set.runs.flat_map { |run| run.branches.filter_map { |id, branch| { rep: run.rep, turn: id, **branch } if branch["expected"] != branch["took"] } },
    richness_commitments: set.runs.map { |run| run.richness.commitments }
  } ]
end
result = {
  protocol: "confirmation-protocol.md", scope: "Unchanged first eight Salt Assizes turns; four runs per arm, not full-script coverage",
  arms: arms,
  verdicts: comparison.verdicts(stories: [ Eval::HELD_OUT ]).map(&:to_h),
  richness: comparison.richness_verdict(stories: [ Eval::HELD_OUT ]).to_h,
  limitation: "Zero standard flags does not establish realism or complete recall. Exploratory manual findings are retained separately; existing scorers and corpora remain unchanged."
}
File.write(directory.join("confirmation-summary.json"), JSON.pretty_generate(result))
puts io.string
puts JSON.pretty_generate(arms)
