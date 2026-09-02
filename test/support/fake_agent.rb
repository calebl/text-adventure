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
  #
  # A QUEUED EXCEPTION IS RAISED INSTEAD OF ANSWERED, so a test can stand a
  # failed call in the middle of a turn's sequence of calls -- the shape
  # `BaseAgent#ask` has once it has exhausted its rotation, which is what a
  # refusal and a suppressed crisis response both look like from out here.
  # Nothing streams first: a test that needs the chunks of a doomed call as
  # well should drive the class under test with its own double.
  # `verify` is run the way `BaseAgent#ask` runs it -- on the parsed content, in
  # place of the attempt loop this fake does not have. So a caller's check still
  # raises here, and a test standing this fake in sees the failure; what it does
  # NOT see is the rotation, because a fake has one queued answer and no models.
  # A test about the rotation itself has to drive a real BaseAgent.
  def ask(prompt, verify: nil)
    @prompts << prompt
    raise "FakeAgent ran out of queued responses" if @responses.empty?

    content = @responses.shift
    raise content if content.is_a?(Class) && content <= Exception
    raise content if content.is_a?(Exception)

    if block_given? && content.is_a?(String)
      content.scan(/\S+\s*/) { |part| yield Chunk.new(part) }
    end

    verify&.call(content)
    Response.new(content)
  end

  # BaseAgent files the messages it wrote under the turn that produced them.
  # A fake writes none, so there is nothing to file -- but the callers do not
  # know which they are holding, which is the point of standing in here.
  def attribute_to!(_scene) = nil

  def recorded_chat = nil
end
