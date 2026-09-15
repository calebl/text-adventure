# Offline confirmation of the exact prepared payloads on the isolated staged
# database. Merely having an unchanged normalized identity is not enough here.
require_relative "evaluate"
require "zlib"

root = RevisedPhysicalClassifierStudy::ROOT
protocol = JSON.parse(root.join("protocol.json").read)
prepared = Zlib::GzipReader.open(root.join("requests.json.gz")) { |file| JSON.parse(file.read) }
# The capture methods construct the production agent before their internal
# no-model guard, then replace its terminal ask. A guard around construction
# itself would forbid reading the actual configured instructions.
actual_protocol = PhysicalClassifierStudy.manifest(concurrency: protocol.fetch("concurrency"), set: protocol.fetch("set"))
raise "Prepared source or corpus changed" unless actual_protocol == protocol
actual = PhysicalClassifierStudy.preflight_requests(Eval::Classifier.corpus)
raise "Prepared actual-ID payloads changed" unless actual == prepared
puts "All #{prepared.size} prepared payloads and source/corpus protocol still match. No provider calls."
