# Finalize retained live readings into receipts, comparisons and provenance.
# It reads the task ledger and OpenRouter credit snapshots without mutating any
# of them, then reuses the standard Result and Comparison implementations.
require "json"
require "zlib"
require "digest"

module DesiresRealizationFinalize
  extend self

  NAME = "desires-realization-20260919".freeze
  ROOT = Rails.root.join("db/eval", NAME)
  MODEL = "mistralai/mistral-medium-3.1".freeze

  def priced(call) = call["provider_cost_usd"] || call.fetch("registry_cost_usd")

  def run
    input = ROOT.join("provider-readings.jsonl")
    attempts = input.readlines.map { |line| JSON.parse(line) }
    successful = attempts.reject { |doc| doc.dig("reading", "error") }
    expected = [ [ Eval::Realization.corpus.cases.first.id, 0 ] ] +
      Eval::Realization.corpus.cases.map(&:id).product((1..Eval::Noise::MIN_RUNS).to_a)
    raise "Incomplete successful result" unless successful.map { |doc| doc.fetch("reading").values_at("id", "rep") }.sort == expected.sort
    raise "A successful call rotated" unless successful.all? { |doc| doc.dig("reading", "answered_by") == MODEL }

    ledger = JSON.parse(File.read(ENV.fetch("EVAL_BUDGET_FILE")))
    raise "Wrong task authorization" unless ledger.fetch("limit_micros") == 1_500_000
    raise "Unsettled budget entry" unless ledger.fetch("entries").all? { |entry| %w[settled unknown].include?(entry.fetch("state")) }
    entries = ledger.fetch("entries")
    successful_receipts = successful.map do |doc|
      row = doc.fetch("reading")
      calls = doc.fetch("provider_calls")
      prefix = "#{NAME}:#{row.fetch('id')}:#{row.fetch('rep')}:"
      matched = entries.select { |entry| entry.fetch("label").start_with?(prefix) && entry.fetch("state") == "settled" }
      raise "Ledger/call count differs for #{row.values_at('id', 'rep').inspect}" unless matched.size == calls.size
      { "id" => row.fetch("id"), "rep" => row.fetch("rep"), "warmup" => row.fetch("rep").zero?,
        "model" => row.fetch("answered_by"), "input_tokens" => row.fetch("input_tokens"),
        "output_tokens" => row.fetch("output_tokens"), "calls" => calls.size,
        "dollars" => calls.sum { |call| priced(call) },
        "provider_cost_missing" => calls.count { |call| call["provider_cost_usd"].nil? },
        "accounted_micros" => matched.sum { |entry| entry.fetch("accounted_micros") },
        "ledger_ids" => matched.map { |entry| entry.fetch("id") }, "error" => nil }
    end
    failed = attempts.select { |doc| doc.dig("reading", "error") }
    failed_entries = entries.select { |entry| entry.fetch("state") == "unknown" }
    raise "Failed attempts and unknown reservations differ" unless failed.size == failed_entries.size
    current_actual = successful_receipts.sum { |receipt| receipt.fetch("dollars") }
    before_credits = JSON.parse(File.read(ENV.fetch("CREDITS_BEFORE")))
    after_credits = JSON.parse(File.read(ENV.fetch("CREDITS_AFTER")))
    credits = { "before" => before_credits, "after" => after_credits,
      "usage_delta" => after_credits.fetch("total_usage") - before_credits.fetch("total_usage"),
      "note" => "OpenRouter account totals bracket the run but may include concurrent account use; per-call receipts are the task attribution." }
    receipt_document = {
      "price_basis" => "Provider-reported dollars where present, otherwise the registry price retained on the same call. Conservative budget accounting is separate.",
      "previous_attempt" => { "actual" => 0.0,
        "reason" => "The first warm-up received a provider rate-limit response with no usage receipt. Its conservative unknown reservation remains charged.",
        "receipts" => failed_entries },
      "current_actual" => current_actual, "actual" => current_actual,
      "receipts" => successful_receipts,
      "authorization" => { "limit_micros" => ledger.fetch("limit_micros"),
        "accounted_micros" => entries.sum { |entry| entry.fetch("accounted_micros") },
        "settled_entries" => entries.count { |entry| entry.fetch("state") == "settled" },
        "unknown_entries" => entries.count { |entry| entry.fetch("state") == "unknown" } },
      "openrouter_credits" => credits
    }
    ROOT.join("receipts.json").write(JSON.pretty_generate(receipt_document) + "\n")

    result = Eval::Realization::Result.load(ROOT)
    old = Eval::Realization::Result.load(Eval.kept_root.join("physical-realization-20260910"))
    matched = Eval::Realization::Result.load(Eval.kept_root.join("desires-before"))
    comparison = Eval::Realization::Comparison.new(old, result)
    raise "Old baseline has another corpus" unless comparison.comparable_corpus?
    File.open(ROOT.join("comparison.txt"), "w") { |file| Eval::Realization::Comparison.new(old, result, io: file).print }
    verdicts = comparison.verdicts(MODEL).map { |row| row.verdict.to_h.merge(direction: row.direction) }
    ROOT.join("verdicts.json").write(JSON.pretty_generate(verdicts) + "\n")
    matched_comparison = Eval::Realization::Comparison.new(matched, result)
    matched_verdicts = matched_comparison.verdicts(MODEL).map { |row| row.verdict.to_h.merge(direction: row.direction) }
    ROOT.join("matched-verdicts.json").write(JSON.pretty_generate(matched_verdicts) + "\n")

    Zlib::GzipWriter.open(ROOT.join("provider-readings.jsonl.gz")) do |file|
      file.mtime = 0
      file.write(input.read)
    end
    input.delete
    source = JSON.parse(ROOT.join("source-manifest.json").read)
    provenance = {
      "completed_at" => result.recorded_at,
      "producer_commit" => source.fetch("producer_commit"),
      "source_manifest_sha256" => Digest::SHA256.file(ROOT.join("source-manifest.json")).hexdigest,
      "repetitions" => result.reps, "cases" => result.corpus_size,
      "successful_readings" => successful.size, "provider_calls" => successful.sum { |doc| doc.fetch("provider_calls").size },
      "interrupted_attempts" => failed.map { |doc| doc.fetch("reading").slice("id", "rep", "error") },
      "estimate_usd" => 0.27338880000000004,
      "allocation_usd" => { "realization" => 0.27338880000000004, "dialogue" => 0.03266928, "task_ceiling" => 1.5 },
      "actual_usd" => current_actual,
      "package_scripts" => %w[run.rb payload_gate.rb finalize.rb].to_h { |path| [ path, Digest::SHA256.file(ROOT.join(path)).hexdigest ] },
      "limitations" => [
        "The broad realization rubric does not score whether the four desire fields are coherent or dramatically useful.",
        "The OpenRouter credit delta is an account-level bracket, not task attribution.",
        "A rate-limited zero-receipt warm-up remains conservatively reserved and is not silently refunded."
      ]
    }
    ROOT.join("run-provenance.json").write(JSON.pretty_generate(provenance) + "\n")
    puts JSON.pretty_generate(readings: successful.size, calls: provenance.fetch("provider_calls"),
      actual_usd: current_actual, accounted_usd: receipt_document.dig("authorization", "accounted_micros").fdiv(1_000_000),
      non_noise_old_baseline_to_new: verdicts.reject { |row| row.fetch(:outcome) == :noise }.map { |row| row.fetch(:code) })
  end
end

DesiresRealizationFinalize.run
