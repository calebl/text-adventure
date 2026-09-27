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

  def sse_events(body)
    body.split("\n\n").filter_map do |frame|
      fields = frame.lines.to_h { |line| line.chomp.split(": ", 2) }
      next unless fields["event"]

      { id: fields["id"].to_i, event: fields["event"], data: JSON.parse(fields["data"]) }
    end
  end
end
