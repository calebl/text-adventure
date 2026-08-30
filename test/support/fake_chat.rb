# Stands in for RubyLLM::Chat so agent and narrator tests never touch a model.
#
# Records everything the object under test configures on it, and returns queued
# responses in order. Deliberately mirrors only the slice of the RubyLLM::Chat
# surface this app uses -- if the app starts calling something else, these
# tests fail loudly rather than quietly passing against a live-looking double.
class FakeChat
  Response = Struct.new(:content)

  attr_reader :prompts, :instructions, :schema, :added_messages, :model_calls, :constructor_options

  # Every FakeChat built through `.install` during a `with_fake_chats` block,
  # oldest first -- so a two-pass agent's chats can be inspected in order.
  def self.built
    Thread.current[:fake_chats_built] ||= []
  end

  # Replaces RubyLLM::Chat.new for the duration of the block. Each construction
  # takes the next queued set of responses.
  def self.with_fake_chats(*response_sets)
    queued = response_sets.dup
    Thread.current[:fake_chats_built] = []

    RubyLLM::Chat.stub(:new, ->(**options) {
      chat = new(*Array(queued.shift), constructor_options: options)
      built << chat
      chat
    }) do
      yield
    end
  ensure
    Thread.current[:fake_chats_built] = nil
  end

  def initialize(*responses, constructor_options: {})
    @responses = responses
    @constructor_options = constructor_options
    @prompts = []
    @added_messages = []
    @model_calls = []
  end

  def with_instructions(instructions)
    @instructions = instructions
    self
  end

  def with_schema(schema)
    @schema = schema
    self
  end

  def with_model(model, **options)
    @model_calls << [ model, options ]
    self
  end

  def add_message(role:, content:)
    @added_messages << { role: role, content: content }
    self
  end

  def messages
    @added_messages.map { |message| Struct.new(:role, :content).new(message[:role], message[:content]) }
  end

  # Mirrors RubyLLM::Chat: the exchange is appended to the transcript, so
  # `messages` grows as the conversation goes on.
  def ask(prompt)
    @prompts << prompt
    raise "FakeChat ran out of queued responses (prompt: #{prompt.to_s.truncate(80)})" if @responses.empty?

    content = @responses.shift
    add_message(role: :user, content: prompt)
    add_message(role: :assistant, content: content)
    Response.new(content)
  end
end
