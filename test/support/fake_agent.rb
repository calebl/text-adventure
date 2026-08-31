# Stands in for BaseAgent so generator tests can run without a model.
# Returns the queued responses in order, one per `ask`.
class FakeAgent
  Response = Struct.new(:content)
  # RubyLLM yields chunks that answer to #content, so the fake ones do too.
  Chunk = Struct.new(:content)

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

  # Given a block, streams the queued response to it a word at a time, the way
  # BaseAgent#ask forwards a block to RubyLLM.
  def ask(prompt)
    @prompts << prompt
    raise "FakeAgent ran out of queued responses" if @responses.empty?

    content = @responses.shift

    if block_given? && content.is_a?(String)
      content.scan(/\S+\s*/) { |part| yield Chunk.new(part) }
    end

    Response.new(content)
  end
end
