# THE MODEL RELAY'S TWO ROUTES. `Relay`'s header is the design; this is the
# order it happens in, and the order is the guarantee:
#
#   1. the bearer token becomes a `Player`, exactly as /api/v1 does it
#      (`Player.authenticate`, digest and constant time); a missing, wrong or
#      revoked token is one 401
#   2. the relay must be configured, or 503
#   3. the per-player rate limit
#   4. the body is read (at most one byte past the ceiling) and checked by
#      `Relay::Request`: route, model, fields, `max_tokens`, size. A refusal
#      here reserves nothing and records nothing
#   5. `Player::Allowance#admit!` checks the headroom and opens the call's
#      `RelayReceipt` holding its worst case, under the player's lock and a
#      transaction -- or answers 402 in the engine's own words, having written
#      nothing
#   6. only then is the request forwarded, and whatever happens to it the
#      receipt is settled
#
# NO BODY IS LOGGED. Rails would parse a JSON body into parameters and log them,
# and on a body that does not parse would log it whole; `#dispatch` sets the
# parameters to nothing before either can happen, and the body is read here as
# bytes. The log line of a relayed call is its path and its status.
#
# ERRORS ARE OPENROUTER'S SHAPE, `{"error": {"code": <status>, "message": ...}}`
# with the relay's own reason in `metadata`, so a client reads a relay refusal
# the way it reads an OpenRouter one. An error from OpenRouter itself is passed
# on as it came, except the three that are about the owner's account (401, 402,
# 403): those are the owner's to fix, and the player gets a 502 that says only
# that no model could be reached.
class Relay::OpenrouterController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods
  include ActionController::Live

  CALLS_PER_MINUTE = 60

  # One store for the process, as `Api::V1::TurnsController` has, so the limit
  # holds in the test environment too.
  RATE_STORE = ActiveSupport::Cache::MemoryStore.new

  ACCOUNT_REFUSALS = [ 401, 402, 403 ].freeze

  OWN_KEY = "or add your own OpenRouter key with `ta key set`".freeze

  before_action :authenticate_player!
  before_action :require_relay!
  rate_limit to: CALLS_PER_MINUTE, within: 1.minute, store: RATE_STORE,
             by: -> { current_player.id },
             with: -> { refuse(429, "rate_limited", "That is more than #{CALLS_PER_MINUTE} relayed calls in a minute. Wait a moment and send it again.") }

  # See the header: the body is never parameters, so it is never logged.
  def dispatch(name, request, response)
    request.request_parameters = {}
    super
  end

  def chat_completions = relay(:chat_completions)

  def decisions = relay(:decisions)

  private

  attr_reader :current_player

  def authenticate_player!
    @current_player = authenticate_with_http_token { |token, _options| Player.authenticate(token) }
    return if @current_player

    headers["WWW-Authenticate"] = %(Bearer realm="text-adventure")
    refuse(401, "unauthorized", "A valid player token is required.")
  end

  def require_relay!
    refuse(503, "not_configured", "This instance does not relay model calls.") unless Relay.configured?
  end

  def relay(route)
    call = Relay::Request.read(route, request.body, content_length: request.content_length)
    receipt = current_player.allowance.admit!(call.reservation, held_for: "the call") do
      RelayReceipt.open!(current_player, call)
    end
    forward(call, receipt)
  rescue Relay::Request::Invalid => e
    refuse(e.status, "invalid_request", e.message)
  rescue Player::Allowance::LimitReached => e
    refuse(402, "limit_reached", "#{e.message.delete_suffix(".")}, #{OWN_KEY}.")
  end

  def forward(call, receipt)
    status = usage = nil
    Relay::Upstream.new.post(call.path, call.forwarded_body) do |upstream|
      status = upstream.status
      if ACCOUNT_REFUSALS.include?(status)
        refuse(502, "upstream_unavailable", "The relay could not reach a model just now.")
      elsif call.stream? && upstream.success?
        usage = pass_stream(upstream)
      else
        usage = pass_body(upstream)
      end
    end
  rescue Relay::Upstream::Unavailable
    refuse(502, "upstream_unavailable", "The relay could not reach a model just now.") unless response.committed?
  ensure
    receipt.settle!(upstream_status: status, usage: usage)
    response.stream.close
  end

  def pass_stream(upstream)
    response.status = upstream.status
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    usage = Relay::StreamUsage.new
    upstream.each_chunk do |chunk|
      usage << chunk
      response.stream.write(Relay.redact(chunk))
    end
    usage.finish
  end

  def pass_body(upstream)
    body = upstream.read
    response.status = upstream.status
    response.headers["Content-Type"] = upstream.content_type.presence || "application/json"
    response.stream.write(Relay.redact(body))
    usage_in(body)
  end

  def usage_in(body)
    parsed = JSON.parse(body)
    parsed["usage"] if parsed.is_a?(Hash)
  rescue JSON::ParserError
    nil
  end

  def refuse(status, reason, message)
    render json: { error: { code: status, message: message, metadata: { reason: reason } } }, status: status
  end
end
