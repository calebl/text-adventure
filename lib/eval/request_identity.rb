# A versioned identity of designated requests assembled against fixed inputs.
# Legacy prompt/corpus fields remain untouched: missing historical schemas
# cannot be reconstructed from today's classes. This is a scaffold identity,
# not a claim that generated conversation history was identical across runs.
# Schema serialization is RubyLLM::Chat#with_schema's executable surface.
module Eval::RequestIdentity
  extend self

  VERSION = 1
  MISSING = "no schema identity recorded".freeze

  # `tools`/`tool_choice` ARE OPTIONAL AND ABSENT BY DEFAULT, so a schema'd
  # request's identity is byte-for-byte what it always was -- `.compact` drops
  # them along with a nil `schema`, which is also what lets a tool-shaped
  # request (no `response_format` at all) carry no `schema` key rather than a
  # misleading nil one. See `Eval::Classifier::ToolShapes` for what builds
  # `tools` and `Eval::Classifier::Version::CaptureAgent` for what calls this
  # with them.
  def request(instructions, prompt, schema, tools: nil, tool_choice: nil)
    { system: instructions, user: prompt, schema: schema&.new&.to_json_schema,
      tools: tools, tool_choice: tool_choice }.compact
  end

  def of(requests)
    { "version" => VERSION, "digest" => Digest::SHA256.hexdigest(JSON.generate(canonical(requests))).first(16) }
  end

  def canonical(value)
    case value
    when Hash then value.stringify_keys.sort.to_h.transform_values { |part| canonical(part) }
    when Array then value.map { |part| canonical(part) }
    else value
    end
  end

  def label(identity)
    identity ? "v#{identity.fetch('version')}:#{identity.fetch('digest')}" : MISSING
  end

  def changed?(before, after)
    before.present? && after.present? && before != after
  end
end
