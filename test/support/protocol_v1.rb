require "json_schemer"

# THE CHECKED-IN PROTOCOL, as a validator. `assert_protocol("Screen", body)`
# validates a parsed response body against `docs/protocol/v1/openapi.json`'s
# schema of that name, so a test asserts conformance to the spec a second
# engine would implement rather than to whatever this engine happens to send.
module ProtocolV1
  DOCUMENT = Rails.root.join("docs/protocol/v1/openapi.json")

  def self.document = @document ||= JSON.parse(DOCUMENT.read)
  def self.openapi = @openapi ||= JSONSchemer.openapi(document)

  def assert_protocol(name, body)
    errors = ProtocolV1.openapi.schema(name).validate(body).map { |error| error["error"] }
    assert_empty errors, "#{name} does not conform to protocol v1:\n#{JSON.pretty_generate(body)}"
  end

  # EVERY EXAMPLE THE SPEC CARRIES, as [schema pointer, value]: each request
  # body's and each response's under `paths`, and each event schema's own.
  def self.examples
    media = document["paths"].flat_map do |path, operations|
      operations.flat_map do |verb, operation|
        at = "#/paths/#{path.gsub("~", "~0").gsub("/", "~1").gsub("{", "%7B").gsub("}", "%7D")}/#{verb}"
        bodies = { "requestBody" => operation["requestBody"], **operation["responses"].transform_keys { |status| "responses/#{status}" } }.compact
        bodies.flat_map do |where, body|
          body["content"].flat_map do |type, content|
            content.fetch("examples", {}).map { |_, example| [ "#{at}/#{where}/content/#{type.sub("/", "~1")}/schema", example["value"] ] }
          end
        end
      end
    end
    events = document["x-events"].values.flat_map do |name|
      document.dig("components", "schemas", name).fetch("examples", []).map { |value| [ "#/components/schemas/#{name}", value ] }
    end
    media + events
  end

  # THE SPEC'S EXAMPLE of what `verb path` answers with `status`.
  def self.example(verb, path, status)
    document.dig("paths", path, verb.to_s, "responses", status.to_s, "content", "application/json", "examples", "example", "value")
  end

  def self.event_example(kind) = document.dig("components", "schemas", document.dig("x-events", kind), "examples", 0)

  # THE SHAPE OF A BODY: every object's keys, at every depth, with the first
  # element of each list standing for all of it. A null on either side says
  # nothing about the other, so an example and a real response compare equal
  # when every object they both have carries the same keys.
  def self.same_shape?(one, other)
    case [ one, other ]
    in [ Hash, Hash ] then one.keys.sort == other.keys.sort && one.all? { |key, value| same_shape?(value, other[key]) }
    in [ Array, Array ] then one.empty? || other.empty? || same_shape?(one.first, other.first)
    else true
    end
  end

  def assert_like_example(example, body)
    assert_not_nil example, "the spec has no example for this"
    assert ProtocolV1.same_shape?(example, body),
           "the spec's example and the engine's response differ in shape:\n#{JSON.pretty_generate(example)}\n---\n#{JSON.pretty_generate(body)}"
  end

  def sse_events(body)
    body.split("\n\n").filter_map do |frame|
      fields = frame.lines.to_h { |line| line.chomp.split(": ", 2) }
      next unless fields["event"]

      { id: fields["id"].to_i, event: fields["event"], data: JSON.parse(fields["data"]) }
    end
  end
end
