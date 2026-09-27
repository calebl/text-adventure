require "test_helper"

# THE MODEL RELAY FROM THE OUTSIDE: real requests and real tokens against a
# stubbed upstream. Nothing here reaches the network -- `Relay::Upstream.new` is
# replaced by `FakeUpstream`, which records what it was asked to send and
# answers what the test told it to.
class RelayTest < ActionDispatch::IntegrationTest
  KEY = "sk-or-v1-owners-key-never-to-be-seen".freeze
  MODEL = BaseAgent::REMOTE_MODEL_IDS.first
  PROMPT = "The secret prompt of the ward at night".freeze

  # One upstream answer, readable the way `Relay::Upstream::Response` is.
  FakeResponse = Struct.new(:status, :content_type, :chunks) do
    def success? = (200..299).cover?(status)
    def each_chunk(&) = chunks.each(&)
    def read = chunks.join
  end

  # Stands in for `Relay::Upstream`. `during` runs while the call is open, as
  # a test's window onto what the relay holds mid-call.
  class FakeUpstream
    attr_reader :calls

    def initialize(response = nil, raises: nil, during: nil)
      @response = response
      @raises = raises
      @during = during
      @calls = []
    end

    def post(path, body)
      @calls << { path: path, body: JSON.parse(body) }
      @during&.call
      raise @raises if @raises

      yield @response
    end
  end

  setup do
    Relay::OpenrouterController::RATE_STORE.clear
    @previous_key = ENV[Relay::KEY_VARIABLE]
    ENV[Relay::KEY_VARIABLE] = KEY
    create(:model, model_id: MODEL, pricing: price(0.4, 2))
    @player, @token = Player.invite!("Ada")
  end

  teardown { ENV[Relay::KEY_VARIABLE] = @previous_key }

  def price(input, output) = { "text_tokens" => { "standard" => { "input_per_million" => input, "output_per_million" => output } } }
  def auth(token = @token) = { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
  def json = JSON.parse(response.body)

  def chat(**fields) = { model: MODEL, messages: [ { role: "user", content: PROMPT } ] }.merge(fields)

  def completion(cost: 0.0012, prompt_tokens: 900, completion_tokens: 150)
    { id: "gen-1", model: MODEL, choices: [ { message: { role: "assistant", content: "The ward is quiet." } } ],
      usage: { prompt_tokens: prompt_tokens, completion_tokens: completion_tokens, cost: cost } }.to_json
  end

  def answered(body = completion, status: 200, type: "application/json")
    FakeUpstream.new(FakeResponse.new(status, type, [ body ]))
  end

  def relay_chat(upstream, body = chat, token: @token)
    Relay::Upstream.stub(:new, upstream) do
      post relay_chat_completions_path, params: body.is_a?(String) ? body : body.to_json, headers: auth(token)
    end
  end

  def capture_log
    log = StringIO.new
    logger = ActiveSupport::Logger.new(log)
    Rails.logger.broadcast_to(logger)
    yield
    log.string
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end

  # --- who is asking ---------------------------------------------------------

  test "no token, a wrong token and a revoked token are the same 401, and nothing is sent" do
    upstream = answered
    Relay::Upstream.stub(:new, upstream) do
      post relay_chat_completions_path, params: chat.to_json, headers: { "Content-Type" => "application/json" }
      assert_response :unauthorized
      refused = response.body

      post relay_chat_completions_path, params: chat.to_json, headers: auth("not-a-token")
      assert_response :unauthorized
      assert_equal refused, response.body

      @player.revoke!
      post relay_decisions_path, params: {}.to_json, headers: auth
      assert_response :unauthorized
      assert_equal refused, response.body
    end

    assert_equal 401, json.dig("error", "code")
    assert_equal "unauthorized", json.dig("error", "metadata", "reason")
    assert_empty upstream.calls
    assert_equal 0, RelayReceipt.count
  end

  test "an instance without the relay key relays nothing" do
    ENV.delete(Relay::KEY_VARIABLE)
    upstream = answered
    relay_chat(upstream)

    assert_response :service_unavailable
    assert_empty upstream.calls
    assert_equal 0, RelayReceipt.count
  end

  # --- what is forwarded -----------------------------------------------------

  test "a chat is forwarded with its ceiling, answered as it came, and its receipt settled from the usage" do
    upstream = answered
    relay_chat(upstream)

    assert_response :ok
    assert_equal "The ward is quiet.", json.dig("choices", 0, "message", "content")
    sent = upstream.calls.sole
    assert_equal "/api/v1/chat/completions", sent[:path]
    assert_equal Relay::Request::MAX_OUTPUT_TOKENS, sent[:body]["max_tokens"], "a request with no ceiling gets the relay's"
    assert_equal PROMPT, sent[:body].dig("messages", 0, "content")

    receipt = @player.relay_receipts.sole
    assert_equal [ "closed", "usage", 900, 150, 200 ],
                 [ receipt.status, receipt.cost_source, receipt.input_tokens, receipt.output_tokens, receipt.upstream_status ]
    # The dearer of the reported $0.0012 and the registry's 900 x 0.4 + 150 x 2 per million.
    assert_equal BigDecimal("0.0012"), receipt.cost_usd
    assert_equal receipt.cost_usd, @player.allowance.spent
    assert_equal 0, @player.allowance.reserved
  end

  test "a decision goes to the decisions route with the pinned Jev and is charged as the hosted engine charges one" do
    upstream = answered({ answers: { "intent" => { "type" => "choice", "choice" => "move" } }, usage: { cost: 0.0001 } }.to_json)
    body = { model: SystemOneAgent::OPENROUTER_MODEL, state: { room: "ward" }, questions: { intent: { type: "choice" } } }
    Relay::Upstream.stub(:new, upstream) { post relay_decisions_path, params: body.to_json, headers: auth }

    assert_response :ok
    assert_equal "/api/alpha/decisions", upstream.calls.sole[:path]
    assert_equal body.deep_stringify_keys, upstream.calls.sole[:body], "a decision is forwarded exactly as sent"
    assert_equal SystemOneReceipt::COST_PER_REQUEST_USD, @player.relay_receipts.sole.cost_usd
  end

  test "only the allowlisted models are forwarded, on each route" do
    upstream = answered
    relay_chat(upstream, chat(model: "openai/gpt-5-pro"))
    assert_response :bad_request
    assert_includes json.dig("error", "message"), MODEL

    relay_chat(upstream, chat(model: "#{MODEL}:online"))
    assert_response :bad_request

    body = { model: MODEL, state: {}, questions: { a: {} } }
    Relay::Upstream.stub(:new, upstream) { post relay_decisions_path, params: body.to_json, headers: auth }
    assert_response :bad_request, "a chat model is not a decision model"

    assert_empty upstream.calls
    assert_equal 0, RelayReceipt.count
  end

  test "a field outside the table is refused by name, never dropped and forwarded" do
    upstream = answered
    { n: 4, models: [ "openai/gpt-5-pro" ], provider: { order: [ "x" ] }, plugins: [ { id: "web" } ], reasoning: { effort: "high" } }.each do |field, value|
      relay_chat(upstream, chat(field => value))
      assert_response :bad_request
      assert_includes json.dig("error", "message"), field.to_s
    end
    relay_chat(upstream, chat(tools: [ { type: "web_search" } ]))
    assert_response :bad_request

    assert_empty upstream.calls
  end

  test "max_tokens past the ceiling is refused" do
    upstream = answered
    relay_chat(upstream, chat(max_tokens: Relay::Request::MAX_OUTPUT_TOKENS + 1))
    assert_response :bad_request
    relay_chat(upstream, chat(max_tokens: "lots"))
    assert_response :bad_request
    assert_empty upstream.calls
  end

  test "an oversize request is refused before it is read or reserved" do
    upstream = answered
    limit = Relay::Request::MAX_BYTES[:chat_completions]
    relay_chat(upstream, chat(messages: [ { role: "user", content: "x" * limit } ]))

    assert_response :content_too_large
    assert_includes json.dig("error", "message"), limit.to_s
    assert_empty upstream.calls
    assert_equal 0, RelayReceipt.count
  end

  test "a body that is not JSON is refused, and neither it nor any prompt reaches the log" do
    upstream = answered
    log = capture_log do
      relay_chat(upstream, "{ \"messages\": \"#{PROMPT}\"")
      assert_response :bad_request
      relay_chat(upstream)
      assert_response :ok
    end

    assert_includes log, "Relay::OpenrouterController", "the log was captured"
    assert_not_includes log, PROMPT
    assert_not_includes log, "The ward is quiet."
  end

  # --- what it may spend -----------------------------------------------------

  test "a call that would pass the limit is refused in the engine's words, with the own-key way out" do
    @player.update!(monthly_limit_usd: BigDecimal("0.01"))
    create(:system_one_receipt, player: @player, cost_usd: BigDecimal("0.009"))
    upstream = answered
    relay_chat(upstream)

    assert_response :payment_required
    message = json.dig("error", "message")
    assert_equal "limit_reached", json.dig("error", "metadata", "reason")
    assert_includes message, "This month's play allowance is used up"
    assert_includes message, "held for the call"
    assert message.end_with?(", or add your own OpenRouter key with `ta key set`."), message
    assert_empty upstream.calls
    assert_equal 0, RelayReceipt.count
  end

  test "an unpriced model is charged dearly, so a small allowance refuses it" do
    Model.where(model_id: MODEL).update_all(pricing: {})
    @player.update!(monthly_limit_usd: BigDecimal("0.10"))
    relay_chat(answered)

    assert_response :payment_required
    assert_operator Relay::Request.new(:chat_completions, chat.to_json).reservation, :>, BigDecimal("0.10")
  end

  test "the call's reservation is held while it is open and released to its real cost after" do
    held = nil
    upstream = answered
    upstream.instance_variable_set(:@during, -> { held = @player.allowance.reserved })
    relay_chat(upstream)

    assert_response :ok
    receipt = @player.relay_receipts.sole
    assert_equal receipt.reserved_usd, held
    assert_operator receipt.reserved_usd, :>, receipt.cost_usd
    assert_equal 0, @player.allowance.reserved
  end

  test "one player's spend is not another's, and a call is filed under whoever sent it" do
    other, other_token = Player.invite!("Bea", monthly_limit_usd: BigDecimal("0.01"))
    create(:system_one_receipt, player: other, cost_usd: BigDecimal("0.01"))

    relay_chat(answered, token: other_token)
    assert_response :payment_required

    relay_chat(answered)
    assert_response :ok
    assert_equal 1, @player.relay_receipts.count
    assert_equal 0, other.relay_receipts.count
    assert_equal BigDecimal("0.01"), other.allowance.spent
  end

  test "a player past the rate limit is refused before anything is read" do
    upstream = answered
    Relay::OpenrouterController::CALLS_PER_MINUTE.times { relay_chat(upstream) }
    relay_chat(upstream)

    assert_response :too_many_requests
    assert_equal Relay::OpenrouterController::CALLS_PER_MINUTE, upstream.calls.size
  end

  # --- a stream --------------------------------------------------------------

  test "a stream is passed through byte for byte and its receipt priced from the final usage chunk" do
    events = [
      ": OPENROUTER PROCESSING\n\n",
      "data: {\"choices\":[{\"delta\":{\"content\":\"The ward \"}}]}\n\n",
      "data: {\"choices\":[{\"delta\":{\"content\":\"is quiet.\"}}]}\n\ndata: {\"choices\":[],\"usage\":{\"prompt_",
      "tokens\":800,\"completion_tokens\":40,\"cost\":0.0009}}\n\n",
      "data: [DONE]\n\n"
    ]
    upstream = FakeUpstream.new(FakeResponse.new(200, "text/event-stream", events))
    relay_chat(upstream, chat(stream: true))

    assert_response :ok
    assert_equal "text/event-stream", response.media_type
    assert_equal events.join, response.body
    assert_equal({ "include_usage" => true }, upstream.calls.sole[:body]["stream_options"])

    receipt = @player.relay_receipts.sole
    assert receipt.stream
    assert_equal [ "usage", 800, 40 ], [ receipt.cost_source, receipt.input_tokens, receipt.output_tokens ]
    assert_equal BigDecimal("0.0009"), receipt.cost_usd
  end

  test "a stream that ends without its usage costs the whole reservation" do
    upstream = FakeUpstream.new(FakeResponse.new(200, "text/event-stream", [ "data: {\"choices\":[]}\n\n" ]))
    relay_chat(upstream, chat(stream: true))

    receipt = @player.relay_receipts.sole
    assert_equal [ "reservation", receipt.reserved_usd ], [ receipt.cost_source, receipt.cost_usd ]
  end

  # --- when OpenRouter fails -------------------------------------------------

  test "an error from OpenRouter is passed on and not charged" do
    error = { error: { code: 400, message: "messages: invalid" } }.to_json
    relay_chat(answered(error, status: 400))

    assert_response :bad_request
    assert_equal error, response.body
    receipt = @player.relay_receipts.sole
    assert_equal [ "declined", 0 ], [ receipt.cost_source, receipt.cost_usd ]
  end

  test "an upstream refusal of the owner's account is the owner's, and the player sees only a 502" do
    account = { error: { code: 401, message: "No auth credentials found for #{KEY}" } }.to_json
    [ 401, 402, 403 ].each do |status|
      relay_chat(answered(account, status: status))
      assert_response :bad_gateway
      assert_not_includes response.body, "credentials"
    end
  end

  test "a network failure is a 502 and costs the reservation, because the call may have been billed" do
    relay_chat(FakeUpstream.new(raises: Relay::Upstream::Unavailable.new("the upstream request failed (Net::ReadTimeout)")))

    assert_response :bad_gateway
    receipt = @player.relay_receipts.sole
    assert_equal [ "reservation", receipt.reserved_usd ], [ receipt.cost_source, receipt.cost_usd ]
  end

  # --- the owner's key -------------------------------------------------------

  test "the owner's key never appears in a response, an error or the log" do
    leaky = { choices: [], echoed: "Bearer #{KEY}", usage: { cost: 0.001 } }.to_json
    bodies = []
    log = capture_log do
      relay_chat(answered(leaky))
      bodies << response.body
      relay_chat(FakeUpstream.new(FakeResponse.new(200, "text/event-stream", [ "data: {\"k\":\"#{KEY}\"}\n\n" ])), chat(stream: true))
      bodies << response.body
      relay_chat(answered("{}", status: 401))
      bodies << response.body
      relay_chat(FakeUpstream.new(raises: Relay::Upstream::Unavailable.new("the upstream request failed (SocketError)")))
      bodies << response.body
      relay_chat(answered, chat(model: "nope"))
      bodies << response.body
    end

    assert_includes log, "Relay::OpenrouterController", "the log was captured"
    assert_not_includes log, KEY
    bodies.each { |body| assert_not_includes body, KEY }
    assert_includes bodies.first, "[REDACTED]"
    RelayReceipt.find_each { |receipt| assert_not_includes receipt.attributes.to_json, KEY }
  end

  test "the player token never appears in a response or the log" do
    log = capture_log { relay_chat(answered) }
    assert_not_includes log, @token
    assert_not_includes response.body, @token
  end
end
