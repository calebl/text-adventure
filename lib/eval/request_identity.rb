# A versioned identity of designated requests assembled against fixed inputs.
# Legacy prompt/corpus fields remain untouched: missing historical schemas
# cannot be reconstructed from today's classes. This is a scaffold identity,
# not a claim that generated conversation history was identical across runs.
# Schema serialization is RubyLLM::Chat#with_schema's executable surface.
module Eval::RequestIdentity
  extend self

  VERSION = 1
  MISSING = "no schema identity recorded".freeze

  def request(instructions, prompt, schema)
    { system: instructions, user: prompt, schema: schema&.new&.to_json_schema }
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
