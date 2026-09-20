# The one way into a System One model, and the counterpart of `BaseAgent`
# rather than a kind of it.
#
# `BaseAgent` wraps a CHAT: instructions, a schema, a conversation that is a row,
# a rotation over models that all speak the same way. A System One request is
# none of that. It sends a `state` object and a MAP OF TYPED QUESTIONS, and gets
# back one typed answer per question -- no messages, no history to continue, no
# schema to be ignored, and nothing to rotate to. Pretending it were a chat
# would have meant `#with_schema` and `#ask` that lie about what is sent, so this
# class exposes `#ask_questions(state:, questions:)` and nothing chat-shaped.
#
# WHAT IT IS FOR: `Playthrough::Classifier::Cascade`, which asks one request of
# ten questions in front of the turn and composes the answer in the engine. See
# that class's header for the rules and `Playthrough::Classifier::Request` for
# the questions.
#
# THE KEY IS THE SWITCH AND THERE IS NO FLAG. `.configured?` is the whole of it:
# with EITHER `TYPESAFE_API_KEY` or `OPENROUTER_API_KEY` in the environment the
# cascade runs, and without either the classifier makes the one model call it
# always made. **An absent key is not an error.** It is deliberately NOT
# `BaseAgent::NoModelConfiguredError` either -- that names a game with no model
# at all, which is a broken install; this names an ordinary machine, including
# every test run and every developer checkout. The owner's rule: either
# credential present means the cascade is on wherever the game already runs.
#
# TWO TRANSPORTS, ONE BOUNDARY. `#ask_questions` and `Answers` stay
# provider-neutral. The HTTP implementation is chosen once at construction:
# TypeSafe direct when `TYPESAFE_API_KEY` is present, otherwise OpenRouter
# Decisions when `OPENROUTER_API_KEY` is present. Each transport owns its
# endpoint, credential variable and pinned model id -- `jev-1.13.0` direct,
# `typesafe/jev-1.13` on OpenRouter. An upgrade of either pin is a deliberate,
# measured change. The request body is otherwise byte-identical between
# transports. OpenRouter's Decisions route is Alpha; every failure still falls
# through to Mistral exactly as today. Treat 32k total tokens as the safe
# context ceiling on OpenRouter.
#
# A FAILURE HERE NEVER BLOCKS A TURN. Every way this class can fail -- a
# timeout, an HTTP error, a body that will not parse, an answer set that does not
# match the questions sent, a choice outside the options sent -- is one error
# family, `Unavailable`, and the one thing its caller does with it is make the
# call it would have made anyway. None of them is an engine refusal: a refusal is
# a reading of the player's line, and these are facts about the network.
# Neither credential is ever logged or written to a receipt, a message row or a
# scene -- `scenes.resolved_by` records that a typed path answered and never
# what authenticated it; which transport answered is kept beside the cascade
# reading for a replay, not as a new scene column.
class SystemOneAgent
  # TypeSafe direct. Read, never logged, never written.
  TYPESAFE_API_KEY_VARIABLE = "TYPESAFE_API_KEY".freeze

  # OpenRouter Decisions. Same discipline: read, never logged, never written.
  OPENROUTER_API_KEY_VARIABLE = "OPENROUTER_API_KEY".freeze

  # Kept as the historical name for the TypeSafe credential so existing call
  # sites that quote the variable in an error keep naming a real one. Prefer
  # the transport-specific constants above for new code.
  API_KEY_VARIABLE = TYPESAFE_API_KEY_VARIABLE

  TYPESAFE_ENDPOINT = URI("https://api.typesafe.ai/v1/systemone").freeze
  OPENROUTER_ENDPOINT = URI("https://openrouter.ai/api/alpha/decisions").freeze

  # Pinned Jev 1.13 on both transports. Floating aliases are deliberately not
  # used: a like-for-like transport claim needs the same release on both sides.
  TYPESAFE_MODEL = "jev-1.13.0".freeze
  OPENROUTER_MODEL = "typesafe/jev-1.13".freeze

  # OpenRouter's published context for this model. TypeSafe direct documents a
  # higher dual limit; treat this as the safe ceiling wherever OpenRouter answers.
  OPENROUTER_CONTEXT_CEILING = 32_000

  TRANSPORT_NAMES = %i[typesafe_direct openrouter_decisions].freeze

  # HOW LONG A TURN WILL WAIT FOR THIS, and it is a live-turn number rather than
  # the benchmark's. The player is waiting on narration and this call sits in
  # front of it; the measured median for a request of this size is about a third
  # of a second, so a wait this long is already many times the answer. What
  # running out costs is one extra Mistral call and no turn at all -- see
  # `#ask_questions`.
  TIMEOUT = 4

  # EVERY WAY THIS CLASS FAILS, and there is one family on purpose. The caller
  # does the same thing with all of them, so telling them apart at the raise
  # site would only invite a caller to start branching on the network.
  class Unavailable < StandardError; end

  # The answer came back and cannot be believed: a missing id, an id nobody
  # asked for, an answer of the wrong type, or a choice outside the options that
  # were sent. Still `Unavailable`, because the outcome is the same.
  class UnusableAnswerError < Unavailable; end

  # WHETHER THIS ENVIRONMENT HAS A SYSTEM ONE CREDENTIAL AT ALL. The cascade's
  # only switch; see the header. Either key turns it on.
  def self.configured?
    ENV[TYPESAFE_API_KEY_VARIABLE].present? || ENV[OPENROUTER_API_KEY_VARIABLE].present?
  end

  # WHICH TRANSPORT A LIVE CONSTRUCTION WOULD PICK, or nil when neither key is
  # present. TypeSafe direct wins when its key is present; OpenRouter is
  # considered only when TypeSafe is absent.
  def self.preferred_transport_name
    return :typesafe_direct if ENV[TYPESAFE_API_KEY_VARIABLE].present?
    return :openrouter_decisions if ENV[OPENROUTER_API_KEY_VARIABLE].present?

    nil
  end

  # Builds the HTTP transport for a named route. The bench pins one explicitly
  # so a measurement arm is never ambient credentials choosing quietly.
  def self.build_transport(name)
    case name.to_sym
    when :typesafe_direct then TypeSafeHttp.new
    when :openrouter_decisions then OpenRouterDecisionsHttp.new
    else
      raise ArgumentError, "#{name.inspect} is not one of #{TRANSPORT_NAMES.inspect}"
    end
  end

  attr_reader :purpose

  # `transport` is the seam the offline engine sweep and the tests stand a
  # fixture in at, the way `BaseAgent.new` is stubbed everywhere else. It answers
  # one method, `#call(body)`, and returns the parsed response body. A real
  # transport also answers `#model` and `#name`; an injected lambda does not,
  # and the ambient preferred transport supplies the model id in that case.
  def initialize(purpose: nil, transport: nil)
    @purpose = purpose
    @transport = transport
  end

  # The transport this agent is speaking, as a stable name a receipt can keep.
  # Nil only when neither credential is present and no transport was injected.
  def transport_name
    return @transport.name if @transport.respond_to?(:name)

    self.class.preferred_transport_name
  end

  # Sends one request and returns an `Answers`. Raises `Unavailable` for every
  # failure, including a key that has gone missing between `.configured?` and
  # here.
  #
  # `questions` is the map the API takes, keyed by ids the caller chose; the ids
  # are not sent to the model and exist only so code can read the answers back.
  def ask_questions(state:, questions:)
    raise Unavailable, "no System One credential in this environment" unless self.class.configured?
    raise Unavailable, "a System One request with no questions" if questions.blank?

    body = { model: model_id, state: state, questions: questions }
    Answers.new(parse(transport.call(body)), questions)
  end

  private

  def transport = @transport ||= self.class.build_transport(self.class.preferred_transport_name)

  def model_id
    return @transport.model if @transport.respond_to?(:model)

    name = self.class.preferred_transport_name || :typesafe_direct
    self.class.build_transport(name).model
  end

  def parse(payload)
    raise UnusableAnswerError, "the provider answered #{payload.class} rather than a body" unless payload.is_a?(Hash)

    payload
  end

  # ONE REQUEST'S ANSWERS, VERIFIED AGAINST THE QUESTIONS THAT WERE SENT.
  #
  # The verification is the point and it is why this is a class rather than a
  # Hash. A Choice is only a closed set because the app closed it, and an answer
  # naming something outside the criteria that were sent would be exactly the
  # out-of-bounds reading the whole design exists to make impossible. So it is
  # checked HERE, once, rather than by each rule that reads an answer.
  #
  # OpenRouter's response envelope may also carry `id`, `provider` and
  # `usage.cost`. Those are kept as provenance on this object and never consulted
  # by the cascade or any other game path.
  class Answers
    attr_reader :usage, :model, :provider, :response_id

    def initialize(payload, questions)
      @answers = payload["answers"]
      @usage = payload["usage"]
      @model = payload["model"]
      @provider = payload["provider"]
      @response_id = payload["id"]
      @questions = questions.deep_stringify_keys

      raise UnusableAnswerError, "the provider answered no `answers` map" unless @answers.is_a?(Hash)

      missing = @questions.keys - @answers.keys
      raise UnusableAnswerError, "the provider did not answer #{missing.join(", ")}" if missing.any?

      validate_usage_provenance!
    end

    # The option chosen for one Choice question, verified to be one of the
    # options that question was sent.
    def choice(id)
      answer = answer_of(id, "choice")
      chosen = answer["choice"]
      options = @questions.fetch(id.to_s).fetch("criteria").keys
      unless options.include?(chosen.to_s)
        raise UnusableAnswerError, "#{id} answered #{chosen.inspect}, which is not one of the options sent"
      end

      chosen.to_s
    end

    # The yes probability for one Noul question, as a Float in 0..1.
    def noul(id)
      reading = answer_of(id, "noul")["noul"]
      unless reading.is_a?(Numeric) && reading >= 0 && reading <= 1
        raise UnusableAnswerError, "#{id} answered #{reading.inspect} rather than a probability"
      end

      reading.to_f
    end

    # Whether a question was asked at all. A target question whose record set is
    # empty is not sent -- see `Playthrough::Classifier::Request` -- and its
    # intent resolves to nothing by construction rather than by an answer.
    def asked?(id) = @questions.key?(id.to_s)

    private

    def validate_usage_provenance!
      return unless @usage.is_a?(Hash) && @usage.key?("cost")

      cost = @usage["cost"]
      return if cost.is_a?(Numeric)

      raise UnusableAnswerError, "usage.cost answered #{cost.inspect} rather than a number"
    end

    def answer_of(id, type)
      answer = @answers[id.to_s]
      raise UnusableAnswerError, "#{id} was answered #{answer.class}" unless answer.is_a?(Hash)
      raise UnusableAnswerError, "#{id} came back as a #{answer["type"]} rather than a #{type}" unless answer["type"] == type

      answer
    end
  end

  # Shared Net::HTTP posting for both transports. Subclasses name the endpoint,
  # credential variable and pinned model; this class never logs either.
  class HttpTransport
    def name = self.class::NAME
    def model = self.class::MODEL

    def call(body)
      endpoint = self.class::ENDPOINT
      request = Net::HTTP::Post.new(endpoint)
      request["Authorization"] = "Bearer #{ENV.fetch(self.class::API_KEY_VARIABLE)}"
      request["Content-Type"] = "application/json"
      request.body = body.to_json

      response = Net::HTTP.start(endpoint.hostname, endpoint.port, use_ssl: true,
                                 open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.request(request)
      end

      # THE STATUS TEXT AND NEVER THE BODY. A 4xx body details the offending
      # field and a 401 body is about a credential; neither belongs in a log
      # line that a player's turn wrote.
      unless response.is_a?(Net::HTTPSuccess)
        raise Unavailable, "the provider answered #{response.code} #{response.message}"
      end

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise UnusableAnswerError, "the provider answered something that is not JSON (#{e.class})"
    rescue Unavailable
      raise
    rescue StandardError => e
      raise Unavailable, "#{e.class}: #{e.message}"
    end
  end

  # TypeSafe's `/v1/systemone` route. Preferred whenever its key is present.
  class TypeSafeHttp < HttpTransport
    NAME = :typesafe_direct
    ENDPOINT = TYPESAFE_ENDPOINT
    API_KEY_VARIABLE = TYPESAFE_API_KEY_VARIABLE
    MODEL = TYPESAFE_MODEL
  end

  # OpenRouter's Alpha Decisions route. Used when TypeSafe's key is absent and
  # `OPENROUTER_API_KEY` is present. Same Choice/Noul body as TypeSafe; only
  # the model id spelling differs.
  class OpenRouterDecisionsHttp < HttpTransport
    NAME = :openrouter_decisions
    ENDPOINT = OPENROUTER_ENDPOINT
    API_KEY_VARIABLE = OPENROUTER_API_KEY_VARIABLE
    MODEL = OPENROUTER_MODEL
  end

  # Historical alias: the original single transport was TypeSafe direct.
  Http = TypeSafeHttp
end
