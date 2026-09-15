# Read the production-configured instructions, then capture each terminal ask
# under the shared no-model guard. No provider call or reservation is made.
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

root = FinalPhysicalClassifierStudy::ROOT
protocol = JSON.parse(root.join("protocol.json").read)
prepared = Zlib::GzipReader.open(root.join("requests.json.gz")) { |file| JSON.parse(file.read) }
actual_protocol = PhysicalClassifierStudy.manifest(concurrency: FinalPhysicalClassifierStudy::CONCURRENCY,
  set: FinalPhysicalClassifierStudy::SET)
raise "Prepared corpus or request identity changed" unless actual_protocol.except("source_files") == protocol.except("source_files")
RubyLLM.config.openrouter_api_key ||= "offline-request-replay"
RubyLLM.config.openrouter_api_base = "http://127.0.0.1:1"
actual = PhysicalClassifierStudy.preflight_requests(Eval::Classifier.corpus)
actual = actual.transform_values { |payload| normalized_payload(payload) }
prepared = prepared.transform_values { |payload| normalized_payload(payload) }
raise "Prepared payloads changed" unless actual == prepared
puts "All #{prepared.size} prepared payloads and corpus/request protocol match. No provider calls."
