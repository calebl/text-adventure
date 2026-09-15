# Buy only the branch cases absent from the completed old corpus. Ordinary
# readings and the original warmup are retained, not purchased a second time.
# EVAL_PREFLIGHT builds the exact first requests without any provider calls.
require "json"
require "digest"
require_relative "support"
require ENV.fetch("EVAL_BUDGET_HELPER")
require_relative "payload_gate"

$stdout.sync = true
ReviewEvalBudget.assert_isolated_database!
package = Pathname.new(__dir__)
source = JSON.parse(package.join("source-manifest.json").read)
source.fetch("files").each do |name, sha|
  raise "Measured source changed: #{name}" unless Digest::SHA256.file(Rails.root.join(name)).hexdigest == sha
end
cases = Eval::Realization.corpus.cases.select { |kase| kase.staging.present? }
raise "Unexpected branch corpus" unless cases.size == 7
requests = PhysicalRealizationEvidence.offline { Eval::Realization::BranchRequests.offline }
identity = PhysicalRealizationEvidence.offline { Eval::Realization::RequestVersion.offline }
legacy = PhysicalRealizationEvidence.offline { Eval::Realization::Version.offline }
if ENV["EVAL_PREFLIGHT"] == "1"
  Eval::Realization::BranchRequests.write!(package, requests)
  package.join("offline-identities.json").write(JSON.pretty_generate({ source: source.fetch("source_sha256"),
    request_identity: identity, legacy: legacy, origin: "Derived offline from unchanged generator inputs; not claimed recorded by the old bench." }) + "\n")
  puts "Offline requests verified: #{requests.size} branches; #{identity.inspect}"
  exit
end
raise "Run preflight before buying calls" unless package.join("requests.json").exist?
raise "Requests changed after preflight" unless JSON.parse(package.join("requests.json").read).fetch("requests") == requests
output = Pathname.new(ENV.fetch("OUT_DIR"))
FileUtils.mkdir_p(output)
path = output.join("branch-readings.jsonl")
saved = path.exist? ? path.readlines.map { |line| JSON.parse(line) } : []
labels = saved.map do |document|
  raise "Wrong saved source" unless document.fetch("source") == source.fetch("source_sha256")
  row = document.fetch("reading")
  raise "An earlier failure requires review" if row["error"]
  [ row.fetch("id"), row.fetch("rep") ]
end
raise "Duplicate saved reading" unless labels.uniq == labels
permitted = cases.map(&:id).product((1..Eval::Noise::MIN_RUNS).to_a)
raise "Saved reading outside the permitted corpus" unless (labels - permitted).empty?
PhysicalRealizationPayload.gate = PhysicalRealizationPayload::Gate.new(requests: requests, allowed: permitted - labels)
ReviewEvalBudget.install!
BaseAgent.prepend(PhysicalRealizationPayload::BeforeBudget)
arm = Eval::Classifier::Arm.parse(ReviewEvalBudget::MODEL)
bench = Eval::Realization::Bench.new(arms: [ arm.id ], io: nil)
arm.pinned do
  (1..Eval::Noise::MIN_RUNS).each do |rep|
    cases.each do |kase|
      next if labels.include?([ kase.id, rep ])

      PhysicalRealizationPayload.gate.current = [ kase.id, rep ]
      ReviewEvalBudget.calls = []
      ReviewEvalBudget.label = "physical-realization:branches:#{kase.id}:#{rep}"
      reading = bench.send(:read, kase, arm, rep)
      document = { source: source.fetch("source_sha256"), reading: reading.to_h,
                   instructions: reading.instructions, provider_calls: ReviewEvalBudget.calls }
      File.open(path, "a") { |file| file.puts(JSON.generate(document)) }
      raise "Failed or rotated branch: #{kase.id}" if reading.failed? || reading.rotated?
      raise "Wrong first request: #{kase.id}" unless Eval::Realization::BranchRequests.canonical(reading.facts.fetch("requests").first) == requests.fetch(kase.id)
      raise "Expected one purchased branch call" unless reading.calls == 1 && ReviewEvalBudget.calls.size == 1
      puts "#{kase.id} rep #{rep}: completed (one paid call)"
    end
  end
end
puts "All branch readings retained."
