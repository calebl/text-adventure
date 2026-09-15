# Offline export only. Rebuild the existing scoring objects from durable
# readings; project old IDs onto the unmodified historical labels separately.
# No model answer is replaced, no failed reading is omitted, and a partial
# repetition cannot become a kept baseline.
require_relative "evaluate"
require "zlib"

module PhysicalClassifierStudy
  def self.export(directory:, destination:, set: SET)
    source = Pathname.new(directory)
    target = Pathname.new(destination)
    protocol = JSON.parse(source.join("protocol.json").read)
    raise "Export names a different study" unless protocol.fetch("set") == set
    journal = Journal.new(source, protocol)
    current = Eval::Classifier.corpus
    historical = Eval::Classifier::Corpus.load(File.join(__dir__, "historical-339-corpus.yml"))
    concurrency = protocol.fetch("concurrency")
    identity = Eval::Classifier::Version.offline
    raise "The measured request identity changed" unless identity == protocol.fetch("request_identity")
    raise "Unexpected measured reading count" unless journal.rows.size == current.size * REPS + 1
    before = Eval::Classifier::Result.load(Eval.kept_root.join("classifier-2026-09-10"))
    raise "Historical corpus changed" unless Eval::Classifier.digest(historical) == before.corpus_digest
    raise "Historical staged positions changed" unless historical.positions == current.positions
    historical.lines.each do |line|
      after = current.lines.find { |entry| entry.id == line.id }
      raise "Historical request changed for #{line.id}" unless after && after.typed == line.typed && after.position == line.position
    end

    recorded_at = JSON.parse(source.join("classifier.json").read).fetch("recorded_at")
    latest = result(journal, corpus: current, identity: identity, name: set, concurrency: concurrency, recorded_at: recorded_at)
    projection = result(journal, corpus: historical, identity: identity, name: "#{set}/historical-339", concurrency: concurrency, recorded_at: recorded_at)
    latest.summary.write!(target)
    projection.summary.write!(target.join("historical-339"))
    File.write(target.join("offline.json"), JSON.pretty_generate(
      "corpus_digest" => Eval::Classifier.digest, "floor" => Eval::Classifier::Offline.new.summary.to_h) + "\n")
    FileUtils.cp(source.join("protocol.json"), target.join("protocol.json"))
    %w[readings.jsonl requests.json].each do |name|
      Zlib::GzipWriter.open(target.join("#{name}.gz")) do |out|
        out.mtime = 0
        File.open(source.join(name), "rb") { |input| IO.copy_stream(input, out) }
      end
    end
    # Compare persisted precision on both sides, just as classifier_compare does.
    # Mixing full-precision live rates with a rounded kept before cannot replay.
    kept_projection = Eval::Classifier::Result.load(target.join("historical-339"))
    comparison = Eval::Classifier::Comparison.new(before, kept_projection, io: nil)
    verdicts = comparison.verdicts(MODEL).select { |row| comparison.judged_metrics.include?(row.metric) }
    File.write(target.join("comparison.json"), JSON.pretty_generate(
      "before" => before.name, "after" => projection.name,
      "before_corpus_digest" => before.corpus_digest, "after_corpus_digest" => projection.corpus_digest,
      "before_request_identity" => before.request_identity, "after_request_identity" => identity,
      "before_concurrency" => before.concurrency, "after_concurrency" => concurrency,
      "suppressed_metrics" => Eval::Classifier::Result::METRICS.keys - comparison.judged_metrics,
      "verdicts" => verdicts.map { |row| { "metric" => row.metric, "verdict" => row.verdict.to_h } },
      "label_changes" => historical.lines.filter_map do |line|
        changed = current.lines.find { |entry| entry.id == line.id }
        next if line.answers == changed.answers
        { "id" => line.id, "historical_answers" => line.answers.map(&:to_s), "current_answers" => changed.answers.map(&:to_s),
          "current_got" => journal.rows.select { |row| row["id"] == line.id && row["rep"].positive? }.map { |row| { "rep" => row["rep"], "answer" => row["answer"] } } }
      end) + "\n")
    ledger = JSON.parse(File.read(ENV.fetch("EVAL_BUDGET_FILE")))
    entries = ledger.fetch("entries").select { |entry| entry.fetch("label").start_with?("#{set}:") }
    calls = journal.rows.flat_map { |row| row.fetch("calls") }
    File.write(target.join("receipts.json"), JSON.pretty_generate(
      "calls_including_warmup" => calls.size, "readings_including_warmup" => journal.rows.size,
      "actual_models" => calls.map { |call| call["actual_model"] }.compact.uniq,
      "state_counts" => entries.group_by { |entry| entry.fetch("state") }.transform_values(&:size),
      "study_accounted_usd" => entries.sum { |entry| entry.fetch("accounted_micros") }.fdiv(1_000_000),
      "registry_priced_usd" => calls.sum { |call| call["registry_cost_usd"].to_f },
      "provider_reported_usd" => calls.sum { |call| call["provider_cost_usd"].to_f },
      "provider_cost_available_calls" => calls.count { |call| !call["provider_cost_usd"].nil? },
      "shared_limit_usd" => ledger.fetch("limit_micros").fdiv(1_000_000),
      "shared_accounted_at_export_usd" => ledger.fetch("entries").sum { |entry| entry.fetch("accounted_micros") }.fdiv(1_000_000)
    ) + "\n")
    latest
  end
end

if ENV["PHYSICAL_CLASSIFIER_MODE"] == "export"
  PhysicalClassifierStudy.export(directory: ENV.fetch("OUT"), destination: __dir__)
end
