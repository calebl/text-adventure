# Read the production-configured instructions, then capture each terminal ask
# under the shared no-model guard. No provider call or reservation is made.
require_relative "evaluate"
require "zlib"

root = FinalPhysicalClassifierStudy::ROOT
protocol = JSON.parse(root.join("protocol.json").read)
prepared = Zlib::GzipReader.open(root.join("requests.json.gz")) { |file| JSON.parse(file.read) }
actual_protocol = PhysicalClassifierStudy.manifest(concurrency: FinalPhysicalClassifierStudy::CONCURRENCY,
  set: FinalPhysicalClassifierStudy::SET)
raise "Prepared source or corpus changed" unless actual_protocol == protocol
actual = PhysicalClassifierStudy.preflight_requests(Eval::Classifier.corpus)
raise "Prepared actual-ID payloads changed" unless actual == prepared
puts "All #{prepared.size} prepared payloads and source/corpus protocol match. No provider calls."
