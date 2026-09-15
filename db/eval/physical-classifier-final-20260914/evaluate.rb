# Third candidate only. Reuse the shared durable journal, exact-request gate,
# scorer, historical audit and budget without editing either measured candidate.
require_relative "../physical-classifier-20260910/evaluate"
require_relative "../physical-classifier-20260910/export"
require_relative "../physical-classifier-20260910/audit"

module FinalPhysicalClassifierStudy
  SET = "physical-classifier-final-20260914".freeze
  ROOT = Pathname.new(__dir__)
  BEFORE = ROOT.join("../physical-classifier-revised-20260910")
  HISTORICAL = ROOT.join("../physical-classifier-20260910")
  CONCURRENCY = 1

  def self.matched_comparison(after, before: Eval::Classifier::Result.load(BEFORE))
    raise "Matched corpus changed" unless before.corpus_digest == after.corpus_digest && before.corpus_size == after.corpus_size
    comparison = Eval::Classifier::Comparison.new(before, after, io: nil)
    { "before" => before.name, "after" => after.name, "corpus_digest" => after.corpus_digest,
      "before_request_identity" => before.request_identity, "after_request_identity" => after.request_identity,
      "before_concurrency" => before.concurrency, "after_concurrency" => after.concurrency,
      "suppressed_metrics" => Eval::Classifier::Result::METRICS.keys - comparison.judged_metrics,
      "verdicts" => comparison.verdicts(PhysicalClassifierStudy::MODEL).map do |row|
        { "metric" => row.metric, "direction" => row.direction, "verdict" => row.verdict.to_h }
      end }
  end

  def self.export(directory:)
    PhysicalClassifierStudy.export(directory: directory, destination: ROOT, set: SET)
    comparison = matched_comparison(Eval::Classifier::Result.load(ROOT))
    File.write(ROOT.join("matched-comparison.json"), JSON.pretty_generate(comparison) + "\n")
    audit = PhysicalClassifierStudy::Audit.run(root: HISTORICAL, after_root: ROOT)
    File.write(ROOT.join("audit.json"), JSON.pretty_generate(audit) + "\n")
  end
end

case ENV["FINAL_CLASSIFIER_MODE"]
when "run"
  $stdout.sync = true
  PhysicalClassifierStudy.run(directory: ENV.fetch("OUT"), concurrency: FinalPhysicalClassifierStudy::CONCURRENCY,
    set: FinalPhysicalClassifierStudy::SET)
when "export"
  FinalPhysicalClassifierStudy.export(directory: ENV.fetch("OUT"))
end
