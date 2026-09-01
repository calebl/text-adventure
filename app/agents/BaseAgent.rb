# base agent wrapping RubyLLM integration
class BaseAgent
  # Raised when a model accepts a schema but answers in prose anyway.
  class SchemaIgnoredError < StandardError; end

  # Raised when the provider rejects our credentials. Deliberately NOT a
  # rotation: see #ask.
  class UnauthorizedProviderError < StandardError; end

  # Models installed locally via ollama. Ordered fastest-and-most-reliable
  # first; `rotate_model` walks down the list when a call fails.
  #
  # `assume_model_exists` is required, not optional: an ollama model is pulled
  # onto the machine and listed by `ollama list`, and is in neither the registry
  # the gem ships nor the `models` table seeded from it. Without the flag a
  # local-only run -- no OPENROUTER_API_KEY -- raised
  # `RubyLLM::ModelNotFoundError` before it ever reached ollama, so every one of
  # these entries was unreachable. Keep the list matching what is actually
  # pulled: nothing validates these names now except ollama itself.
  LOCAL_MODEL_OPTIONS = [
    {
      provider: :ollama,
      model: "gemma3:12b",
      assume_model_exists: true
    },
    {
      provider: :ollama,
      model: "gpt-oss:20b",
      assume_model_exists: true
    },
    {
      provider: :ollama,
      model: "qwen3:8b",
      assume_model_exists: true
    },
    {
      provider: :ollama,
      model: "qwen3:4b",
      assume_model_exists: true
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

  attr_reader :instructions, :schema, :model_options, :purpose

  def self.default_model_options
    if ENV["OPENROUTER_API_KEY"].present?
      remote_model_options + LOCAL_MODEL_OPTIONS
    else
      LOCAL_MODEL_OPTIONS
    end
  end

  # `purpose`, `playthrough` and `character` are what the conversation gets
  # FILED UNDER once it exists -- see Chat. They are the whole of what this
  # class knows about the game, and it knows that much only so a written row is
  # findable afterwards.
  #
  # `chat` is for the one conversation that is PICKED UP rather than started:
  # hand in a `Chat` (`Chat.conversation_with`) and its stored messages are the
  # history this agent continues from. Everything else gets a fresh one.
  def initialize(instructions = nil, schema = nil,
                 model_options: self.class.default_model_options,
                 purpose: nil, playthrough: nil, character: nil, chat: nil)
    @model_options = model_options
    @current_model_index = 0
    @purpose = purpose
    @playthrough = playthrough
    @character = character
    @initial_chat = chat
    @recorded_message_ids = []

    with_instructions(instructions) if instructions
    with_schema(schema) if schema

    self
  end

  # THE CONVERSATION, built on first use rather than in the constructor.
  #
  # Lazily, because a `Chat` is a row now: several classes here build an agent
  # they may never ask anything (a location that turns out to be realized
  # already, a classifier the debug view only wants the candidate lists from),
  # and none of them should leave an empty conversation behind.
  def chat
    @chat ||= build_chat
  end

  # The persisted conversation, or nil if this agent never asked anything. The
  # non-building reader -- callers attributing a turn's cost must not create a
  # chat by looking for one.
  def recorded_chat
    @chat if @chat.is_a?(Chat)
  end

  # Asks the model, rotating to the next configured model when a call fails.
  # Raises once the attempts are exhausted rather than returning nothing --
  # a silent failure here reads downstream as "the AI produced garbage".
  #
  # A block is forwarded to RubyLLM, which then streams the answer into it chunk
  # by chunk. Rotating restarts the stream from the beginning, so a streaming
  # caller can see the opening of a failed attempt before the retry arrives.
  #
  # A 401 is the one failure that does NOT rotate. Rotating is right for a model
  # that failed; the fix for a rejected key is a key, not a different model. And
  # because the local ollama models sit at the bottom of the same list, rotating
  # on a 401 quietly answers from a 4k-context CPU model with nothing anywhere
  # saying the remote call was ever refused -- every downstream measurement and
  # every quality guarantee silently becomes about a different model. Fail loud.
  #
  # A FAILED ATTEMPT IS ROLLED BACK BEFORE THE RETRY, and it has to be. RubyLLM
  # persists the prompt before it sends it, so without the rewind a rotation
  # would re-ask on top of the messages the failed attempt left behind: the
  # second attempt would send the prompt twice, and a model that answered in
  # prose would still be sitting in the history the replacement model is handed.
  # `#rewind_to` puts the conversation back where the attempt found it, so every
  # attempt asks the same question in the same context.
  def ask(prompt, &block)
    attempts = 0

    begin
      attempts += 1
      # The conversation is built BEFORE the mark is taken, or the first ask of
      # a fresh agent would mark an empty nothing and record no messages.
      conversation = chat
      mark = conversation_mark
      response = conversation.ask(prompt, &block)
      verify_schema_honored!(response)
      record_exchange(mark)
      response
    rescue RubyLLM::UnauthorizedError => e
      rewind_to(mark)
      raise UnauthorizedProviderError, unauthorized_message(e)
    rescue => e
      rewind_to(mark)

      if attempts < MAX_ATTEMPTS && attempts < @model_options.count
        Rails.logger.warn { "#{current_model[:model]} failed (#{e.class}: #{e.message}), rotating model" }
        rotate_model
        retry
      end

      raise
    end
  end

  def add_message(role:, content:)
    chat.add_message(role: role, content: content)
  end

  # STAMPS THIS AGENT'S MESSAGES WITH THE TURN THEY WERE EXCHANGED ON, so
  # `Playthrough::Debug` can total what one turn cost and name the model that
  # actually answered it. Called by whoever created the Scene, because the scene
  # does not exist until after the call that produced it.
  #
  # On the messages rather than on the chat: a durable conversation (Chat::CHARACTER)
  # contributes two messages to this turn and two to the next.
  def attribute_to!(scene)
    return if scene.nil? || @recorded_message_ids.empty?

    Message.where(id: @recorded_message_ids, scene_id: nil).update_all(scene_id: scene.id)
  end

  # Takes the same option shape as MODEL_OPTIONS entries. RubyLLM's `with_model`
  # wants the id positionally and spells the flag `assume_exists`, so translate.
  #
  # Only ever applied to a chat that exists: a fresh one is built pointed at
  # `current_model` already, so rotating before the first ask has nothing to say.
  def with_model(model:, provider: nil, assume_model_exists: false)
    @chat&.with_model(model, provider: provider, assume_exists: assume_model_exists)
    self
  end

  # Instructions and schema are held until the conversation is built, so that
  # configuring an agent stays free -- see #chat.
  def with_schema(schema)
    @schema = schema
    @chat&.with_schema(schema)
    self
  end

  def with_instructions(instructions)
    @instructions = instructions
    @chat&.with_instructions(instructions)
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

  # A conversation is a row, and this is where it becomes one: pointed at
  # `current_model`, filed under the game records that will need to find it, and
  # given whatever instructions and schema were configured before now.
  #
  # `assume_model_exists` is carried through from the model options for the same
  # reason it is set there -- an ollama model is in neither registry, so without
  # it saving the chat raises `RubyLLM::ModelNotFoundError` before anything is
  # asked.
  def build_chat
    conversation = @initial_chat || Chat.new(purpose: purpose, playthrough: @playthrough, character: @character)
    resuming = conversation.persisted?
    apply_model(conversation)
    # PICKING A CONVERSATION UP IS WHERE IT GETS TRIMMED. RubyLLM rebuilds the
    # request out of every persisted message, so a chat that kept more history
    # than it means to send would send it -- see Chat#prune_history!.
    conversation.prune_history! if resuming
    conversation.with_instructions(@instructions) if @instructions
    conversation.with_schema(@schema) if @schema
    conversation
  end

  def apply_model(conversation)
    conversation.assume_model_exists = current_model[:assume_model_exists]
    conversation.model = current_model[:model]
    conversation.provider = current_model[:provider]
    conversation.save!
  end

  # Where the conversation stood before an attempt, so the attempt can be undone.
  # Nil for an agent whose chat is not persisted -- the tests inject a fake one.
  def conversation_mark
    recorded_chat && (recorded_chat.messages.maximum(:id) || 0)
  end

  def rewind_to(mark)
    return if mark.nil? || recorded_chat.nil?

    recorded_chat.messages.where("id > ?", mark).destroy_all
  end

  # What this agent has written, so `#attribute_to!` can find it later.
  def record_exchange(mark)
    return if mark.nil? || recorded_chat.nil?

    @recorded_message_ids.concat(recorded_chat.messages.where("id > ?", mark).pluck(:id))
  end

  def unauthorized_message(error)
    provider = current_model[:provider]
    key_hint = provider == :openrouter ? "OPENROUTER_API_KEY" : "the #{provider} credentials"

    "#{provider} rejected our credentials (#{error.class}: #{error.message}). " \
      "Check #{key_hint} -- NOT rotating to another model, because a rejected " \
      "key is not fixed by a different model and a silent local fallback would " \
      "hide it."
  end

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
