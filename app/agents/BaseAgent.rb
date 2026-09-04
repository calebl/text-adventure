# base agent wrapping RubyLLM integration
class BaseAgent
  # Raised when a model accepts a schema but answers in prose anyway.
  class SchemaIgnoredError < StandardError; end

  # Raised when the provider rejects our credentials. Deliberately NOT a
  # rotation: see #ask.
  class UnauthorizedProviderError < StandardError; end

  # Raised when there is no model to ask at all: no `OPENROUTER_API_KEY`, and
  # the local rotation off (which it is unless `TA_LOCAL_MODELS` says
  # otherwise). A sentence naming the two ways out beats a `NoMethodError` on
  # nil three frames down.
  class NoModelConfiguredError < StandardError; end

  # THE PARENT OF THE TWO FAILURES WHOSE TEXT MUST NEVER BE KEPT, so a caller
  # that persists prose can discard both in one rescue without having to know
  # which one happened (`Scene::Narrator#narrate`). What `#ask` DOES about them
  # is not shared, and must not be -- see the two subclasses.
  class UnusableResponseError < StandardError; end

  # Raised when an unschema'd call came back as prose ABOUT the request instead
  # of prose answering it: a decline, or a menu of alternatives to pick from.
  #
  # A FAILED CALL, on the same side of the line as a schema a model ignored, so
  # `#ask` rotates. That is the whole point: measured over 51 charged narrator
  # prompts, `minimax/minimax-m3` refused 8 and `mistralai/mistral-medium-3.1`
  # refused none of them, including every one minimax would not write. The app
  # had the model it needed and could not reach it, because a refusal is a
  # 200 OK. See BaseAgent::Refusal and `data/ta-refusal-range/report.md`.
  #
  # That measurement is also why mistral is now FIRST in REMOTE_MODEL_IDS, and
  # a rotation off it lands on minimax rather than on a model known to comply.
  # Read the note on the constant before reasoning about what this rescue buys.
  class RefusalError < UnusableResponseError; end

  # Raised when a model answered with real-world crisis resources -- a suicide
  # hotline, delivered by a character in a world with no telephones.
  #
  # DELIBERATELY NOT A ROTATION, and the one failure in this class that is not
  # a claim about the model being wrong. Another model in the list narrates the
  # same exchange in fiction with no intervention, so rotating would be the
  # app quietly routing around a safety response. That is a decision somebody
  # has to make on purpose rather than a side effect of a detector, and it was
  # made: suppress the model's version so it never becomes a `Scene`, and show
  # an app-authored message outside the fiction instead. `#ask` re-raises this
  # without rotating; `NarrationJob` is what shows the message. See
  # `Playthrough::SafetyNotice`.
  class CrisisResponseError < UnusableResponseError; end

  # NOT AN ERROR CLASS OF ITS OWN, AND DELIBERATELY SO --
  # `SanitizesGeneratedText::TruncatedTextError` is the failure a caller's
  # `verify:` check raises when a field arrived at exactly the `max_length` its
  # schema asked it to stay under. The rule and the caps belong to the concern
  # and to the schema; what belongs HERE is the same thing recorded for every
  # class above: whether it rotates.
  #
  # IT ROTATES, on the same side of the line as `SchemaIgnoredError`. A field
  # cut off mid-word is a model that did not deliver the shape it was asked for,
  # which is what `SchemaIgnoredError` already buys a second model for. Treating
  # the two differently was never chosen -- it was only where the raise happened.
  #
  # WHERE THE RAISE HAPPENS IS THE WHOLE FIX. `InteractionAgent#ask` called the
  # sanitizer AFTER `#ask` had returned, so the rotation never saw it: on
  # `minimax/minimax-m3`, 15 of 16 attempted narrations died this way and 1 of 18
  # turns completed (`data/ta-conversation-read/report.md` §4) -- every one of
  # them a turn a second model would have written. Raising outside the loop also
  # left the rejected exchange sitting in the character's DURABLE conversation,
  # because `#ask`'s rewind is what takes a failed attempt back out.
  #
  # SO ONLY THE RAISE MOVED, NOT THE CHECK. The check reads parsed fields
  # against caps their own schema declares, which is `SanitizesGeneratedText`'s
  # business and not this class's; this class knows nothing about `max_length`
  # and should not start. `ask(verify:)` is the seam: the caller keeps the check,
  # `#ask` runs it inside the attempt loop, and the rescue below does what it
  # does for every other failed call.

  # Models installed locally via ollama.
  #
  # OFF BY DEFAULT SINCE 2026-09-03, and reachable only through
  # `TA_LOCAL_MODELS=1`. The captain's ruling, in his words: *"If we are still
  # falling back to local models, let's stop doing that for now."* The reason is
  # that a local fallback does not fail -- it ANSWERS, slowly, from a
  # 4k-context CPU model, and every measurement and quality guarantee
  # downstream silently becomes about a different model. That is the same
  # argument `#ask` already makes for not rotating on a 401, applied to the
  # rest of the rotation.
  #
  # THE LIST IS KEPT RATHER THAN DELETED because "for now" is what he said, and
  # because a machine with no key and no network is a real way to work on this
  # app. Turning it back on is one environment variable. See
  # `.local_model_options`.
  #
  # Ordered fastest-and-most-reliable first; `rotate_model` walks down the list
  # when a call fails.
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
  # present. They are an order of magnitude faster than ollama, which matters
  # for the generate-as-you-explore loop.
  #
  # `mistralai/mistral-medium-3.1` is FIRST because it was measured to be the
  # model that writes the turn. Over 51 charged narrator prompts plus 32
  # interaction exchanges, on the app's own prompts and schemas, it refused
  # 0 of 52 cases -- including every one of the 8 `minimax/minimax-m3` refused
  # (16%) -- broke no frames, and dropped no required `Interaction::Schema`
  # field in 14 talk turns where minimax dropped them in 12 of 41 (29%). It is
  # also 3-4x faster: median 2.4s against 8.8s, range 1.7-4.3s against
  # 2.2-62.5s. See `data/ta-refusal-range/report.md`.
  #
  # THE ACCEPTED COST, written down so nobody rediscovers it as a regression:
  # mistral writes noticeably thinner prose -- about 60% of minimax's length on
  # the narrator path (median 614 against 1016 characters). That trade was made
  # on purpose. Do not try to buy the length back by editing prompts without
  # deciding it again.
  #
  # THE INTERACTION-PATH HALF OF THAT CLAIM WAS WRONG, and it is corrected here
  # rather than deleted, because it is the kind of number somebody reinstates.
  # This comment used to say mistral wrote "under a third on the interaction
  # path -- 176 against 602". The 602 was measured before the truncation guard
  # existed, over a five-field schema whose `pre_thought` was capped at 200
  # characters -- and 30 of minimax's 39 character sheets in that sweep carried
  # a field cut off mid-word at exactly 200 (`data/ta-conversation-read/report.md`
  # §5 item 5), which the narrator pass then wrote fluent prose over. So 602 is
  # not a length minimax delivers; it is a length it delivered while the app was
  # not yet noticing that the answers were fragments. There is no measured
  # interaction-path length for either model to compare, and the comparison is
  # not made until there is one.
  #
  # WHAT THE ORDER COSTS THE SAFETY NET, also on purpose: `RefusalError` rotates
  # so a refusal reaches a model that will write the turn. With mistral first, a
  # refusal-triggered rotation now lands on minimax -- the model that refuses --
  # so the rotation no longer has a known-compliant model to fall to. That is
  # acceptable on the measurement (mistral refused nothing in 52 cases) but it
  # is a real change in what the net buys: the second model is now a fallback
  # for rate limits and bad days, not a known answer to a refusal.
  #
  # `minimax/minimax-m3` is second.
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
    "mistralai/mistral-medium-3.1",
    "minimax/minimax-m3"
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

  # PROVIDER-SPECIFIC REQUEST PARAMETERS, AND THERE ARE NONE.
  #
  # EMPTY BY DEFAULT AND EMPTY IN EVERY SHIPPED PATH: nothing in `app/` ever
  # replaces this, so no call the player's turn makes carries a provider
  # parameter and no remote request changes shape. `BaseAgent::ProviderParamsTest`
  # pins that -- an empty answer here and no `with_params` on the built chat --
  # because a default that quietly grew a parameter would change every call in
  # the app at once.
  #
  # WHY THE SEAM EXISTS AT ALL, on the captain's ruling of 2026-09-04. Ollama
  # takes `think: false` as a REQUEST field, and a thinking model answers the
  # classifier in 2.95 seconds without it against over 120 with it -- a 40-fold
  # difference on the one call a player waits for. `Eval::Classifier::Arm`
  # replaces this for the length of a bench pass so a local arm can be measured
  # at the speed the model is capable of, and the bench reports the thinking-on
  # figure beside it so the board shows BOTH what the model can do and what this
  # app would get today. The instrument reaching in here is the alternative to
  # the instrument reaching through `#chat` to reconfigure a live conversation.
  #
  # IT IS NOT A FEATURE AND MUST NOT BECOME ONE. Making the app fast on ollama
  # is a change to the app, decided on its own evidence; this is a measurement
  # asking a question.
  def self.default_provider_params = {}

  # THE LOCAL HALF OF THE ROTATION, which is empty unless somebody asked for
  # it. See the note on LOCAL_MODEL_OPTIONS for why the default changed.
  def self.local_model_options
    ENV["TA_LOCAL_MODELS"].present? ? LOCAL_MODEL_OPTIONS : []
  end

  # WHAT THIS AGENT WILL ASK, in order. It can be EMPTY -- no key and no
  # `TA_LOCAL_MODELS` -- and that is deliberate: an empty rotation fails loudly
  # at `#apply_model` with a sentence saying what to set, which is a better
  # outcome than a turn answered by a model nobody chose.
  def self.default_model_options
    (ENV["OPENROUTER_API_KEY"].present? ? remote_model_options : []) + local_model_options
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
  #
  # `verify` is a caller's OWN check on the parsed answer, run inside the
  # attempt loop so whatever it raises is a failed call like any other. It
  # exists for one check that cannot live in this file and must not live outside
  # the loop -- see the truncation note beside the error classes at the top.
  def ask(prompt, verify: nil, &block)
    attempts = 0

    begin
      attempts += 1
      # The conversation is built BEFORE the mark is taken, or the first ask of
      # a fresh agent would mark an empty nothing and record no messages.
      conversation = chat
      mark = conversation_mark
      response = conversation.ask(prompt, &block)
      verify_schema_honored!(response)
      # CRISIS BEFORE REFUSAL, and the order IS the decision rather than a
      # style choice. One response can be both -- the corpus has a resource
      # card that is also structurally a refusal -- and if the refusal check
      # ran first the app would rotate, which is the outcome that was
      # explicitly not chosen. See CrisisResponseError.
      verify_no_crisis_response!(response)
      verify_not_refused!(response)
      # LAST, AND INSIDE THE LOOP. The caller's check on the parsed answer, so a
      # truncated field is a failed call the rotation can see rather than an
      # exception thrown past it. Before `record_exchange`: a rejected attempt
      # is about to be rewound, so nothing should have filed its messages.
      verify&.call(response.content)
      record_exchange(mark)
      response
    rescue RubyLLM::UnauthorizedError => e
      rewind_to(mark)
      raise UnauthorizedProviderError, unauthorized_message(e)
    rescue CrisisResponseError
      # Rewound but NOT rotated. The rewind is the suppression: the text does
      # not stay in the persisted conversation either, so nothing anywhere is
      # holding a copy of what the caller is about to refuse to show.
      rewind_to(mark)
      raise
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

  # HOW MUCH THE MODEL IS ALLOWED TO WANDER. Unset by default, which is the
  # provider's default and right for prose. A call that picks from a closed
  # enum wants none of it: `Playthrough::Classifier` is the caller, and a
  # classifier that answers the same input two different ways on two runs is
  # noise in the drift counter. Applied to the conversation when it is built
  # and carried across a rotation, since `with_model` keeps the same
  # underlying chat.
  def with_temperature(temperature)
    @temperature = temperature
    @chat&.with_temperature(temperature)
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
    conversation.with_temperature(@temperature) unless @temperature.nil?
    # LAST, AND EMPTY IN EVERY SHIPPED PATH. See `.default_provider_params`.
    params = self.class.default_provider_params
    conversation.with_params(**params) if params.present?
    conversation
  end

  def apply_model(conversation)
    raise NoModelConfiguredError, no_model_message if current_model.nil?

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

  # The two ways out, named, because the answer to "no model" is a setting and
  # not a code change.
  def no_model_message
    "No model is configured. Set OPENROUTER_API_KEY for the hosted rotation " \
      "(#{self.class::REMOTE_MODEL_IDS.join(", ")}), or TA_LOCAL_MODELS=1 to use " \
      "the ollama models installed on this machine -- which is off by default " \
      "because a slow local answer is worse than a loud failure. See BaseAgent::LOCAL_MODEL_OPTIONS."
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

  # WHAT A REFUSAL IS, and why it is a failed call. `BaseAgent::Refusal` carries
  # the rule and the measurement; this is only the seam that acts on it.
  #
  # UNSCHEMA'D CALLS ONLY. A schema'd call that came back as prose is already a
  # failure by the check above, and a schema'd call that came back as the Hash
  # it was asked for is not prose at all -- reading a character's five fields
  # for a first-person "I" would flag every character who says "I" about
  # themselves, which is all of them.
  def verify_not_refused!(response)
    return unless @schema.nil?
    return unless Refusal.refused?(response.content)

    flags = Refusal.flags(response.content)
    # COUNT IT. The observation that started this was "the repo has no record of
    # a refusal ever being a problem" -- which meant nothing, because nothing
    # would have recorded one. Tagged so a refusal is greppable and countable in
    # a log without parsing prose.
    Rails.logger.warn do
      "[refusal] #{current_model[:model]} declined #{purpose || "an unschema'd call"} " \
        "(#{flags.join(', ')}), treating it as a failed call"
    end

    raise RefusalError,
          "#{current_model[:model]} declined the prompt instead of answering it (#{flags.join(', ')})"
  end

  # A crisis response is the one shape the structural rule cannot see, because
  # it arrives inside quoted dialogue. Same unschema'd gate, and for a second
  # reason on top of the first: no schema'd response in the measured corpus
  # carried one, so reading them would be untested surface.
  def verify_no_crisis_response!(response)
    return unless @schema.nil?
    return unless Refusal.crisis_response?(response.content)

    Rails.logger.warn do
      "[crisis] #{current_model[:model]} answered #{purpose || "an unschema'd call"} with " \
        "real-world crisis resources; suppressing it and NOT rotating"
    end

    raise CrisisResponseError,
          "#{current_model[:model]} answered with real-world crisis resources"
  end

  def missing_schema_keys(content)
    return [] unless @schema.respond_to?(:required_properties)

    @schema.required_properties.map(&:to_s).reject do |key|
      content[key].present? || content[key] == false
    end
  end
end
