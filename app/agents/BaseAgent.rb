# base agent wrapping RubyLLM integration
class BaseAgent
  MODEL_OPTIONS = [
    {
      provider: :ollama,
      model: "gemma3:1b"
    },
    {
      provider: :ollama,
      model: "qwen3:0.6b"
    },
    {
      provider: :ollama,
      model: "llama3.2:3b"
    }
  ]

  attr_reader :chat, :instructions, :schema

  def initialize(instructions = nil, schema = nil)
    @current_model_index = 0
    @chat = RubyLLM::Chat.new(
      **MODEL_OPTIONS.first
    )

    with_instructions(instructions) if instructions
    with_schema(schema) if schema

    self
  end

  def ask(prompt)
    @chat.ask(prompt)
  end

  def add_message(role:, content:)
    @chat.add_message(role: role, content: content)
  end

  def with_model(**args)
    @chat.with_model(**args)
    self
  end

  def with_schema(schema)
    @schema = schema
    @chat.with_schema(schema)
    self
  end

  def with_instructions(instructions)
    @instructions = instructions
    @chat.with_instructions(instructions)
    self
  end

  def rotate_model
    @current_model_index = (@current_model_index + 1) % MODEL_OPTIONS.count
    @chat.with_model(**MODEL_OPTIONS[@current_model_index])
    self
  end

  def current_model
    MODEL_OPTIONS[@current_model_index]
  end
end
