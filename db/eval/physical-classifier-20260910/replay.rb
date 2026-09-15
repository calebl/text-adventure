# Re-score both views from the kept raw readings. No paid database, ledger or
# provider is needed; the model guard makes an accidental call fail loudly.
require_relative "evaluate"
require_relative "audit"
require "zlib"
require "tmpdir"

root = Pathname.new(__dir__)
protocol = JSON.parse(root.join("protocol.json").read)
EngineSweep.without_a_model do
  Dir.mktmpdir do |directory|
    Zlib::GzipReader.open(root.join("readings.jsonl.gz")) do |input|
      File.open(File.join(directory, "readings.jsonl"), "wb") { |out| IO.copy_stream(input, out) }
    end
    journal = PhysicalClassifierStudy::Journal.new(directory, protocol)
    corpora = {
      root => Eval::Classifier::Corpus.load(root.join("source/classifier_corpus.yml")),
      root.join("historical-339") => Eval::Classifier::Corpus.load(root.join("historical-339-corpus.yml"))
    }
    corpora.each do |path, corpus|
      kept = Eval::Classifier::Result.load(path)
      rebuilt = PhysicalClassifierStudy.result(journal, corpus: corpus, identity: kept.request_identity,
        name: kept.name, concurrency: kept.concurrency, recorded_at: kept.recorded_at).summary
      raise "Stored scores changed for #{kept.name}" unless JSON.parse(JSON.generate(rebuilt.to_h)) == JSON.parse(JSON.generate(kept.to_h))
    end
    before = Eval::Classifier::Result.load(Eval.kept_root.join("classifier-2026-09-10"))
    after = Eval::Classifier::Result.load(root.join("historical-339"))
    comparison = Eval::Classifier::Comparison.new(before, after, io: nil)
    verdicts = comparison.verdicts(PhysicalClassifierStudy::MODEL).select { |row| comparison.judged_metrics.include?(row.metric) }
    actual = verdicts.map { |row| { "metric" => row.metric, "verdict" => row.verdict.to_h } }
    expected = JSON.parse(root.join("comparison.json").read).fetch("verdicts")
    raise "Comparison changed" unless JSON.parse(JSON.generate(actual)) == expected
    audit = JSON.parse(JSON.generate(PhysicalClassifierStudy::Audit.run(root: root)))
    raise "Unchanged-case audit changed" unless audit == JSON.parse(root.join("audit.json").read)
    puts "All #{journal.rows.size} retained readings rescore identically as current343 and historical339; verdicts match. No model calls."
  end
end
