# Preserve complete branch provider evidence and the experiment's actual costs,
# then perform the offline replay/comparison. The shared ledger is read under a
# shared file lock; this command never reserves, rewrites, or resets it.
require "json"
require "zlib"
require "digest"

package = Pathname.new(__dir__)
input = Pathname.new(ENV.fetch("OUT_DIR")).join("branch-readings.jsonl")
branches = input.readlines.map { |line| JSON.parse(line) }
expected = Eval::Realization.corpus.cases.select { |kase| kase.staging.present? }.map(&:id).product((1..Eval::Noise::MIN_RUNS).to_a)
labels = branches.map { |doc| doc.fetch("reading").values_at("id", "rep") }
raise "Incomplete branch result; retain evidence and resume missing readings" unless labels.sort == expected.sort
raise "A branch failed" if branches.any? { |doc| doc.fetch("reading")["error"] }
Zlib::GzipWriter.open(package.join("branch-provider-readings.jsonl.gz")) do |file|
  file.mtime = 0
  file.write(input.read)
end
legacy = Zlib::GzipReader.open(package.join("legacy/provider-readings.jsonl.gz")) do |file|
  file.each_line.map { |line| JSON.parse(line) }
end
ledger = File.open(ENV.fetch("EVAL_BUDGET_FILE"), "r") do |file|
  file.flock(File::LOCK_SH)
  JSON.parse(file.read)
end
canonical = Eval::Realization::BranchRequests.method(:canonical)
digest = ->(receipt) { Digest::SHA256.hexdigest(JSON.generate(canonical.call(receipt))) }
priced = ->(receipt) { receipt["provider_cost_usd"] || receipt.fetch("registry_cost_usd") }
entries = ledger.fetch("entries").select { |entry| entry.fetch("label").start_with?("physical-realization:") }
indexed = entries.group_by { |entry| digest.call(entry.fetch("receipt")) }
used = []
receipts = (legacy + branches).map do |doc|
  row = doc.fetch("reading")
  calls = doc.fetch("provider_calls")
  matched = calls.map do |call|
    matches = indexed.fetch(digest.call(call))
    raise "Ambiguous ledger provenance" unless matches.one?
    used << matches.first.fetch("id")
    matches.first
  end
  { id: row.fetch("id"), rep: row.fetch("rep"), warmup: row.fetch("rep").zero?,
    model: row.fetch("answered_by"), input_tokens: row.fetch("input_tokens"), output_tokens: row.fetch("output_tokens"),
    calls: calls.size, dollars: calls.sum { |call| priced.call(call) },
    provider_cost_missing: calls.count { |call| call["provider_cost_usd"].nil? },
    accounted_micros: matched.sum { |entry| entry.fetch("accounted_micros") },
    ledger_ids: matched.map { |entry| entry.fetch("id") }, error: row["error"] }
end
raise "A paid call was counted twice" unless used.uniq == used
abandoned = entries.reject { |entry| used.include?(entry.fetch("id")) }
raise "Unresolved realization reservation" unless entries.all? { |entry| entry.fetch("state") == "settled" }
current_actual = receipts.sum { |row| row.fetch(:dollars) }
previous_actual = abandoned.sum { |entry| priced.call(entry.fetch("receipt")) }
receipt_document = {
  price_basis: "Provider-reported dollars where present, otherwise pinned registry-priced token usage. Conservative shared-ledger accounting is separate.",
  previous_attempt: { actual: previous_actual, reason: "Paid partial realization abandoned at the earlier cap; its completed replacement is counted among measured readings.", receipts: abandoned },
  current_actual: current_actual, actual: current_actual + previous_actual, receipts: receipts,
  shared_authorization: { limit_micros: ledger.fetch("limit_micros"), authorizations: ledger.fetch("authorizations", []),
    entries: ledger.fetch("entries").size, accounted_micros: ledger.fetch("entries").sum { |entry| entry.fetch("accounted_micros") },
    note: "This is a read-only snapshot of the cumulative ledger, which also covers other evaluation programs. No prior charge was cleared." }
}
package.join("receipts.json").write(JSON.pretty_generate(receipt_document) + "\n")
provenance = {
  completed_at: File.mtime(input).utc.iso8601,
  legacy_measured_readings: legacy.count { |doc| doc.fetch("reading").fetch("rep").positive? },
  original_warmups: legacy.count { |doc| doc.fetch("reading").fetch("rep").zero? },
  new_branch_readings: branches.size,
  original_source: "b5197572b1b0a6607497072ff06be208efabb5db3a903bf517276af950744b67",
  current_source: JSON.parse(package.join("source-manifest.json").read).fetch("source_sha256"),
  derived_evidence: "Legacy full requests are reconstructed from retained paid prompts, system messages, emitted schemas and structured answers. Message#extract_content deterministically serializes the prior assistant answer with JSON.generate. Replay verifies current prompt/schema and every recorded admission for all old readings.",
  offline_identity: "The schema-aware scaffold fingerprint was assembled offline after the benchmark instrumentation landed. It is not claimed to have been recorded by the older run.",
  first_branch_stop: "The first new reading passed the pre-send allowlist and was paid/saved. An in-memory symbol/string post-call comparison stopped the runner. Parsed evidence matched exactly; only post-call canonicalization changed before resuming without buying it again.",
  limitations: [ "Different corpus sizes are compared separately: preserved legacy22 and current29, never relabeled as one corpus.",
                "The broader realization rubric does not score physical item profile correctness; the targeted physical corpus supplies that evidence.",
                "Some legacy cast inputs are random but recorded. Offline execution replay restores their recorded slots rather than drawing different people.",
                "The run resumed after a budget pause. Per-reading latencies and the original warmup are retained; no speed improvement is inferred from the pause." ]
}
package.join("run-provenance.json").write(JSON.pretty_generate(provenance) + "\n")
load package.join("replay.rb")
