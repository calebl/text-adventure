# Offline confirmation of the exact prepared payloads on the isolated staged
# database. Merely having an unchanged normalized identity is not enough here.
#
# The stored protocol also records a digest of every app and seed-world file, as
# a record of the tree the set was prepared on. Those digests are evidence and
# are not compared: any unrelated change to app code moves one, so comparing
# them turned this check red for reasons that say nothing about the requests.
# What is compared is the corpus, the request identity and every prepared
# payload -- the same gate the final set's verify.rb applies.
#
# This set is historical: the final set's revision superseded its requests, so
# on a current tree the corpus or the request identity no longer matches and
# there is nothing live to compare the payloads with. That is reported as what
# it is and exits cleanly; it is not breakage, and this file is not a gate for
# current work. Only a matching identity with differing payloads raises.
require_relative "evaluate"
require "zlib"

def normalized_payload(payload)
  copy = payload.deep_dup
  prefix, heading, rest = copy.fetch("user").partition("## Physical Actions (token: one attempt)\n")
  actions, player_heading, typed = rest.partition("## The Player Types\n")
  tokens = {}
  actions = actions.lines.each_with_index.map do |line, index|
    token = line.split(": ", 2).first
    next line unless token.match?(/\Ause:[^:]+:(?:\d+:){3}\d+\z/)

    tokens[token] = "physical-action-#{index}"
    line.sub(token, tokens.fetch(token))
  end.join
  copy["user"] = prefix + heading + actions + player_heading + typed
  copy["schema"] = normalize_schema(copy.fetch("schema"), tokens)
  copy
end

def normalize_schema(value, tokens)
  case value
  when Hash
    value.to_h do |key, part|
      [ key, key == "enum" ? part.map { |entry| tokens.fetch(entry, entry) } : normalize_schema(part, tokens) ]
    end
  when Array then value.map { |part| normalize_schema(part, tokens) }
  else value
  end
end

root = RevisedPhysicalClassifierStudy::ROOT
protocol = JSON.parse(root.join("protocol.json").read)
prepared = Zlib::GzipReader.open(root.join("requests.json.gz")) { |file| JSON.parse(file.read) }
# The capture methods construct the production agent before their internal
# no-model guard, then replace its terminal ask. A guard around construction
# itself would forbid reading the actual configured instructions.
actual_protocol = PhysicalClassifierStudy.manifest(concurrency: protocol.fetch("concurrency"), set: protocol.fetch("set"))
moved = %w[corpus_digest corpus_size request_identity].reject { |key| actual_protocol[key] == protocol[key] }
unless moved.empty?
  puts "Historical set: the live #{moved.join(', ')} no longer match what these payloads were prepared " \
       "against, so they are not compared. Expected on a current tree. No provider calls."
  exit
end
raise "Prepared protocol changed" unless actual_protocol.except("source_files") == protocol.except("source_files")
RubyLLM.config.openrouter_api_key ||= "offline-request-replay"
RubyLLM.config.openrouter_api_base = "http://127.0.0.1:1"
actual = PhysicalClassifierStudy.preflight_requests(Eval::Classifier.corpus)
actual = actual.transform_values { |payload| normalized_payload(payload) }
prepared = prepared.transform_values { |payload| normalized_payload(payload) }
raise "Prepared actual-ID payloads changed" unless actual == prepared
puts "All #{prepared.size} prepared payloads and corpus/request protocol still match. No provider calls."
