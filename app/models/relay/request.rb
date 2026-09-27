# ONE CALL A PLAYER ASKED THE RELAY TO FORWARD, read, checked, and priced at its
# worst case before anything is reserved or sent.
#
# Everything the relay will forward is decided here, and it is a closed set:
#
#   the route    one of `ROUTES`, fixed by the path, never by the body
#   the model    `BaseAgent::REMOTE_MODEL_IDS` for a chat, the pinned Jev for a
#                decision -- exactly what the engine itself calls, and nothing
#                an environment override or a player could add
#   the fields   `FIELDS` for the route; any other top-level field is refused
#                by name rather than dropped, so a client learns it was not
#                sent. Fields that would multiply or widen the bill (`n`,
#                `models`, `provider`, `plugins`, `reasoning`, ...) are simply
#                not in the table
#   the output   `max_tokens` at most `MAX_OUTPUT_TOKENS`; a request that sets
#                none is sent with the ceiling, so no call is unbounded
#   the size     at most `MAX_BYTES` for the route, refused before it is parsed
#
# THE RESERVATION IS THE CALL'S WORST CASE, derived the way the evaluation
# benches bound a call before they send it (`Eval::Arrival::Budget`): the
# request's bytes plus `MESSAGE_OVERHEAD_TOKENS` bound its input tokens -- a
# token is never shorter than a byte -- and its `max_tokens` bounds its output.
# Both are priced from the registry by `Player::Allowance.price`, which charges
# a model it cannot price at `Player::Allowance::UNPRICED_PER_MILLION`. The same
# three constants as the benches, so the bound is one the project already
# trusts: `MAX_BYTES[:chat_completions]` is the bench's `MAX_INPUT_BYTES`.
#
# A decision is not priced by the token: the registry has no price for Jev, and
# the hosted engine already charges every System One request
# `SystemOneReceipt::COST_PER_REQUEST_USD`, raised to what the provider
# reports. The relay charges the same call the same way, so the route a player
# takes does not change what it costs them. Its size ceiling keeps it inside
# `SystemOneAgent::OPENROUTER_CONTEXT_CEILING`.
class Relay::Request
  ROUTES = {
    chat_completions: "/api/v1/chat/completions",
    decisions: "/api/alpha/decisions"
  }.freeze

  MAX_BYTES = { chat_completions: 65_536, decisions: 32_768 }.freeze
  MESSAGE_OVERHEAD_TOKENS = 4_096
  MAX_OUTPUT_TOKENS = 2_048

  # The top-level fields each route forwards. A chat's are the ones the
  # engine's own OpenRouter requests carry; a decision's are the three
  # `SystemOneAgent#ask_questions` sends.
  FIELDS = {
    chat_completions: %w[model messages stream stream_options temperature top_p seed stop
                         max_tokens tools tool_choice parallel_tool_calls response_format].freeze,
    decisions: %w[model state questions].freeze
  }.freeze

  # A refusal of the request as sent, before anything is reserved. `status` is
  # the HTTP answer; the message says which rule, and never quotes the body.
  class Invalid < StandardError
    attr_reader :status

    def initialize(message, status: 400)
      @status = status
      super(message)
    end
  end

  def self.models(route) = route == :decisions ? [ SystemOneAgent::OPENROUTER_MODEL ] : BaseAgent::REMOTE_MODEL_IDS

  # Reads at most one byte past the route's ceiling from `io`, so an oversize
  # body is refused without being held in memory.
  def self.read(route, io, content_length: nil)
    limit = MAX_BYTES.fetch(route)
    raise Invalid.new(too_large(limit), status: 413) if content_length.to_i > limit

    raw = io.read(limit + 1).to_s
    raise Invalid.new(too_large(limit), status: 413) if raw.bytesize > limit

    new(route, raw)
  end

  def self.too_large(limit) = "A relayed request may be at most #{limit} bytes."

  attr_reader :route, :bytes, :body

  def initialize(route, raw)
    @route = route
    @bytes = raw.bytesize
    @body = parse(raw)
    check!
  end

  def path = ROUTES.fetch(route)
  def model = body["model"]
  def stream? = body["stream"] == true
  def max_tokens = body["max_tokens"]

  # What is sent upstream: the body as read, with the output ceiling filled in
  # when the request set none, and usage asked for on a stream so its cost can
  # be read off the final chunk.
  def forwarded_body
    sent = body.dup
    if route == :chat_completions
      sent["max_tokens"] ||= MAX_OUTPUT_TOKENS
      sent["stream_options"] = { "include_usage" => true } if stream?
    end
    JSON.generate(sent)
  end

  def reservation
    return SystemOneReceipt::COST_PER_REQUEST_USD if route == :decisions

    price = Player::Allowance.price(model)
    input = bytes + MESSAGE_OVERHEAD_TOKENS
    output = max_tokens || MAX_OUTPUT_TOKENS
    ((input * price[:input] + output * price[:output]) / 1_000_000).round(6, BigDecimal::ROUND_UP)
  end

  private

  def parse(raw)
    parsed = JSON.parse(raw)
    raise Invalid, "A relayed request is one JSON object." unless parsed.is_a?(Hash)

    parsed
  rescue JSON::ParserError
    raise Invalid, "A relayed request is one JSON object."
  end

  def check!
    extra = body.keys - FIELDS.fetch(route)
    raise Invalid, "The relay does not forward #{extra.sort.join(", ")}." if extra.any?

    allowed = self.class.models(route)
    raise Invalid, "The relay forwards only #{allowed.join(", ")}." unless allowed.include?(model)

    route == :decisions ? check_decision! : check_chat!
  end

  def check_chat!
    raise Invalid, "A chat request needs a list of messages." unless body["messages"].is_a?(Array) && body["messages"].any?
    unless max_tokens.nil? || (max_tokens.is_a?(Integer) && max_tokens.between?(1, MAX_OUTPUT_TOKENS))
      raise Invalid, "max_tokens must be a whole number from 1 to #{MAX_OUTPUT_TOKENS}."
    end
    unless body["stream"].nil? || [ true, false ].include?(body["stream"])
      raise Invalid, "stream must be true or false."
    end

    tools = body["tools"]
    return if tools.nil?
    return if tools.is_a?(Array) && tools.all? { |tool| tool.is_a?(Hash) && tool["type"] == "function" }

    raise Invalid, "The relay forwards only function tools."
  end

  def check_decision!
    raise Invalid, "A decision request needs a state object." unless body["state"].is_a?(Hash)
    raise Invalid, "A decision request needs a map of questions." unless body["questions"].is_a?(Hash) && body["questions"].any?
  end
end
