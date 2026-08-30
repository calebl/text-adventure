# Stands in for BaseAgent so generator tests can run without a model.
# Returns the queued responses in order, one per `ask`.
class FakeAgent
  Response = Struct.new(:content)

  attr_reader :prompts, :schemas, :instructions

  def initialize(*responses)
    @responses = responses
    @prompts = []
    @schemas = []
  end

  def with_instructions(instructions)
    @instructions = instructions
    self
  end

  def with_schema(schema)
    @schemas << schema
    self
  end

  def ask(prompt)
    @prompts << prompt
    raise "FakeAgent ran out of queued responses" if @responses.empty?

    Response.new(@responses.shift)
  end
end
