# Offline, no model: re-score a stored classifier set's readings against the
# corpus as it stands, and write the result as a new set. SRC is a set directory
# whose readings were kept; DEST is where the re-scored set goes; KEEP_ROWS=1
# keeps the rows in the written file (a cascade set's convention).
#
# Only the scoring moves. Each reading's answer is rebuilt from the `got` it
# stored and judged by the same `Reading` predicates the bench uses; the figures
# that do not depend on a label -- latency, rotations, failures and the omission
# count, which needs the provider's raw JSON the rows do not carry -- are kept
# from the original pass.
LABEL_FREE = %w[latency_median latency_p95 rotations failures failures_by_class also_omitted].freeze
PATTERN = /\A(?<intent>\w+) -> (?<target>.+?)(?: \(and (?<also>.+)\))?\z/

corpus = Eval::Classifier.corpus
source = JSON.parse(File.read(Pathname(ENV.fetch("SRC")).join(Eval::Classifier::RESULTS)))
passes = source.fetch("passes").map do |stored|
  readings = stored.fetch("readings").map do |row|
    line = corpus.lines.detect { |candidate| candidate.id == row.fetch("id") } or raise "no corpus line #{row["id"]}"
    answer = nil
    if row["got"]
      parsed = PATTERN.match(row["got"]) or raise "unparsed answer #{row["got"].inspect}"
      target = parsed[:target] == Eval::Classifier::NONE ? nil : parsed[:target]
      answer = Eval::Classifier::Corpus::Answer.new(intent: parsed[:intent].to_sym, target: target, also_named: parsed[:also])
    end
    Eval::Classifier::Bench::Reading.new(line: line, arm: stored.fetch("arm"), rep: stored.fetch("rep"), answer: answer,
                                         answered_by: row["answered_by"], raw: nil, seconds: row["seconds"],
                                         error: row["error"], resolved_by: row["resolved_by"],
                                         target_present: row["target_present"],
                                         named_more_than_one: row["named_more_than_one"], out_of_set: row["out_of_set"],
                                         system_one_transport: row["system_one_transport"])
  end
  pass = Eval::Classifier::Bench::Pass.new(arm: stored.fetch("arm"), rep: stored.fetch("rep"), readings: readings)
  pass.to_h.transform_keys(&:to_s).merge(stored.slice(*LABEL_FREE))
end
rescored = Eval::Classifier::Result.new(
  name: File.basename(ENV.fetch("DEST")), recorded_at: source["recorded_at"],
  corpus_size: corpus.size, corpus_digest: Eval::Classifier.digest(corpus), request_identity: source["request_identity"],
  arms: source.fetch("arms"), reps: source["reps"], concurrency: source["concurrency"], cascade: source["cascade"],
  warmups: source["warmups"].to_a, answered_by: source["answered_by"],
  passes: passes.map { |row| Eval::Classifier::Result::Stored.new(row) })
rescored = rescored.summary(keep_rows: ENV["KEEP_ROWS"] == "1") unless ENV["WHOLE"] == "1"
rescored.write!(ENV.fetch("DEST"))
puts "#{ENV["DEST"]}: corpus #{rescored.corpus_digest}"
