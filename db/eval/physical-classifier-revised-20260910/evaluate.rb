# Reuse the exact-request gate, durable journal and shared spending ledger.
# A distinct set name keeps every initial-candidate request and charge intact.
# No provider call is permitted by the preflight branch.
require_relative "../physical-classifier-20260910/evaluate"
require_relative "../physical-classifier-20260910/export"
require_relative "../physical-classifier-20260910/audit"

module RevisedPhysicalClassifierStudy
  SET = "physical-classifier-revised-20260910".freeze
  ROOT = Pathname.new(__dir__)
  BEFORE = ROOT.join("../physical-classifier-20260910")

  def self.export(directory:)
    PhysicalClassifierStudy.export(directory: directory, destination: ROOT, set: SET)
    before = Eval::Classifier::Result.load(BEFORE)
    after = Eval::Classifier::Result.load(ROOT)
    raise "Matched corpus changed" unless before.corpus_digest == after.corpus_digest && before.corpus_size == after.corpus_size
    comparison = Eval::Classifier::Comparison.new(before, after, io: nil)
    File.write(ROOT.join("matched-comparison.json"), JSON.pretty_generate(
      "before" => before.name, "after" => after.name, "corpus_digest" => after.corpus_digest,
      "before_request_identity" => before.request_identity, "after_request_identity" => after.request_identity,
      "before_concurrency" => before.concurrency, "after_concurrency" => after.concurrency,
      "suppressed_metrics" => Eval::Classifier::Result::METRICS.keys - comparison.judged_metrics,
      "verdicts" => comparison.verdicts(PhysicalClassifierStudy::MODEL).map do |row|
        { "metric" => row.metric, "direction" => row.direction, "verdict" => row.verdict.to_h }
      end) + "\n")
    File.write(ROOT.join("audit.json"), JSON.pretty_generate(PhysicalClassifierStudy::Audit.run(root: BEFORE, after_root: ROOT)) + "\n")
  end
end

case ENV["REVISED_CLASSIFIER_MODE"]
when "run"
  $stdout.sync = true
  PhysicalClassifierStudy.run(directory: ENV.fetch("OUT"), concurrency: Integer(ENV.fetch("CONCURRENCY", "2")),
    set: RevisedPhysicalClassifierStudy::SET)
when "export"
  RevisedPhysicalClassifierStudy.export(directory: ENV.fetch("OUT"))
end
