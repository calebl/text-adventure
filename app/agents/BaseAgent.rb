# base agent wrapping RubyLLM integration
class BaseAgent
  # Raised when a model accepts a schema but answers in prose anyway.
  class SchemaIgnoredError < StandardError; end

  # Models installed locally via ollama. Ordered fastest-and-most-reliable
  # first; `rotate_model` walks down the list when a call fails.
  LOCAL_MODEL_OPTIONS = [
    {
      provider: :ollama,
      model: "gemma3:12b"
    },
    {
      provider: :ollama,
      model: "gpt-oss:20b"
    },
    {
      provider: :ollama,
      model: "qwen3:8b"
    },
    {
      provider: :ollama,
      model: "qwen3:4b"
    }
  ]

  # Hosted models, tried ahead of the local ones whenever OPENROUTER_API_KEY is
  # present. They are an order of magnitude faster, which matters for the
  # generate-as-you-explore loop. The second entry is a fallback for when the
  # first is rate limited or having a bad day.
  #
  # Every model here MUST support structured outputs. Check before adding one:
  #   curl -s https://openrouter.ai/api/v1/models \
  #     | jq '.data[] | select(.id == "MODEL") | .supported_parameters'
  #
  # This is not optional diligence. A model without it does not fail -- it
  # returns prose, which is far worse. OpenRouter's `:free` endpoints are the
  # usual offenders: `minimax/minimax-m3` honors schemas while
  # `minimax/minimax-m3:free` silently does not. See #verify_schema_honored!.
  REMOTE_MODEL_IDS = [
    "minimax/minimax-m3",
    "mistralai/mistral-medium-3.1"
  ]

  MAX_ATTEMPTS = 3

  def self.remote_model_options
    ids = REMOTE_MODEL_IDS.dup
    ids.unshift(ENV["OPENROUTER_MODEL"]) if ENV["OPENROUTER_MODEL"].present?

    ids.uniq.map do |id|
      { provider: :openrouter, model: id, assume_model_exists: true }
    end
  end

  attr_reader :chat, :instructions, :schema, :model_options

  def self.default_model_options
    if ENV["OPENROUTER_API_KEY"].present?
      remote_model_options + LOCAL_MODEL_OPTIONS
    else
      LOCAL_MODEL_OPTIONS
    end
  end

  def initialize(instructions = nil, schema = nil, model_options: self.class.default_model_options)
    @model_options = model_options
    @current_model_index = 0
    @chat = RubyLLM::Chat.new(**current_model)

    with_instructions(instructions) if instructions
    with_schema(schema) if schema

    self
  end

  # Asks the model, rotating to the next configured model when a call fails.
  # Raises once the attempts are exhausted rather than returning nothing --
  # a silent failure here reads downstream as "the AI produced garbage".
  def ask(prompt)
    attempts = 0

    begin
      attempts += 1
      response = @chat.ask(prompt)
      verify_schema_honored!(response)
      response
    rescue => e
      if attempts < MAX_ATTEMPTS && attempts < @model_options.count
        Rails.logger.warn { "#{current_model[:model]} failed (#{e.class}: #{e.message}), rotating model" }
        rotate_model
        retry
      end

      raise
    end
  end

  def add_message(role:, content:)
    @chat.add_message(role: role, content: content)
  end

  # Takes the same option shape as MODEL_OPTIONS entries. RubyLLM's `with_model`
  # wants the id positionally and spells the flag `assume_exists`, so translate.
  def with_model(model:, provider: nil, assume_model_exists: false)
    @chat.with_model(model, provider: provider, assume_exists: assume_model_exists)
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

  # Swaps the model in place so the conversation so far is preserved --
  # multi-step generators depend on the earlier turns still being there.
  def rotate_model
    @current_model_index = (@current_model_index + 1) % @model_options.count
    with_model(**current_model)
  end

  def current_model
    @model_options[@current_model_index]
  end

  private

  # Some models -- notably OpenRouter's `:free` endpoints -- accept a JSON
  # schema and then fail to honor it. Two distinct ways, both silent:
  #
  #   1. Answering in prose. Callers index the result with `content["field"]`,
  #      and Ruby's String#[] does substring matching, so a prose response
  #      yields the field name back instead of raising.
  #   2. Returning a Hash with only some of the fields. The missing ones read
  #      as nil and surface much later as "can't be blank" validation errors,
  #      after the expensive call has already been paid for.
  #
  # Both are treated as failed calls so `ask` rotates to a model that complies.
  def verify_schema_honored!(response)
    return if @schema.nil?

    content = response.content

    unless content.is_a?(Hash)
      raise SchemaIgnoredError,
            "#{current_model[:model]} ignored the schema and returned #{content.class}"
    end

    missing = missing_schema_keys(content)
    return if missing.empty?

    raise SchemaIgnoredError,
          "#{current_model[:model]} omitted schema fields: #{missing.join(', ')}"
  end

  def missing_schema_keys(content)
    return [] unless @schema.respond_to?(:required_properties)

    @schema.required_properties.map(&:to_s).reject do |key|
      content[key].present? || content[key] == false
    end
  end
end
