require "test_helper"

# THE PROVIDER BOUNDARY. Two things are worth pinning here and the rest belongs
# to the caller: that an absent key is not an error but an absent cascade, and
# that every way a request can come back unbelievable is ONE error family, so no
# caller is ever invited to branch on the network.
class SystemOneAgentTest < ActiveSupport::TestCase
  # The suite deletes both System One credentials at boot (see `test_helper.rb`),
  # so a test that wants one sets it and puts it back.
  def with_env(overrides)
    prior = {}
    overrides.each do |key, value|
      prior[key] = ENV[key]
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
    yield
  ensure
    prior.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end

  def with_typesafe(value = "a-test-typesafe-key", &block)
    with_env("TYPESAFE_API_KEY" => value, &block)
  end

  def with_openrouter(value = "a-test-openrouter-key", &block)
    with_env("OPENROUTER_API_KEY" => value, &block)
  end

  QUESTIONS = {
    "intent" => { "type" => "choice", "instructions" => "which?", "criteria" => { "take" => "a", "other" => "b" } },
    "here" => { "type" => "noul", "instructions" => "is it?" }
  }.freeze

  CHOICE = { "type" => "choice", "choice" => "take", "probabilities" => {}, "confidence" => 1.0 }.freeze
  NOUL = { "type" => "noul", "noul" => 0.9 }.freeze

  def body(answers, model: SystemOneAgent::TYPESAFE_MODEL, extra: {})
    { "model" => model, "answers" => answers, "usage" => { "input_tokens" => 1, "output_tokens" => 1 } }.merge(extra)
  end

  def ask(answers, questions: QUESTIONS, env: { "TYPESAFE_API_KEY" => "a-test-typesafe-key" },
          transport: nil, extra: {})
    sent = []
    agent = SystemOneAgent.new(transport: transport || ->(request) { sent << request; body(answers, extra: extra) })
    with_env(env) { [ agent.ask_questions(state: { "player_action" => "take it" }, questions: questions), sent.first, agent ] }
  end

  # --- the key is the switch ------------------------------------------------

  test "either credential alone says whether there is a cascade at all" do
    assert_not SystemOneAgent.configured?, "the suite must run keyless by default"

    with_typesafe { assert SystemOneAgent.configured? }
    with_openrouter { assert SystemOneAgent.configured? }
    with_typesafe("") { assert_not SystemOneAgent.configured?, "an empty TypeSafe key is not a key" }
    with_openrouter("") { assert_not SystemOneAgent.configured?, "an empty OpenRouter key is not a key" }
  end

  # An absent key is an ordinary machine, not a broken install -- so it is
  # deliberately NOT `BaseAgent::NoModelConfiguredError`, which names a game
  # with no model at all.
  test "asking with no credential is unavailable and never a missing model" do
    error = assert_raises(SystemOneAgent::Unavailable) do
      SystemOneAgent.new(transport: ->(_) { body({}) }).ask_questions(state: {}, questions: QUESTIONS)
    end

    assert_not_kind_of BaseAgent::NoModelConfiguredError, error
    assert_includes error.message, "System One credential"
  end

  # --- transport selection --------------------------------------------------

  test "TypeSafe direct wins when its key is present, even beside OpenRouter" do
    with_env("TYPESAFE_API_KEY" => "typesafe-key", "OPENROUTER_API_KEY" => "openrouter-key") do
      assert_equal :typesafe_direct, SystemOneAgent.preferred_transport_name
      assert_instance_of SystemOneAgent::TypeSafeHttp, SystemOneAgent.build_transport(:typesafe_direct)
      assert_equal :typesafe_direct, SystemOneAgent.new.transport_name
    end
  end

  test "OpenRouter Decisions is selected only when TypeSafe is absent" do
    with_openrouter do
      assert_equal :openrouter_decisions, SystemOneAgent.preferred_transport_name
      assert_equal :openrouter_decisions, SystemOneAgent.new.transport_name
    end

    with_env("TYPESAFE_API_KEY" => nil, "OPENROUTER_API_KEY" => nil) do
      assert_nil SystemOneAgent.preferred_transport_name
    end
  end

  test "all four credential combinations resolve as the owner's precedence" do
    with_env("TYPESAFE_API_KEY" => nil, "OPENROUTER_API_KEY" => nil) do
      assert_not SystemOneAgent.configured?
      assert_nil SystemOneAgent.preferred_transport_name
    end

    with_env("TYPESAFE_API_KEY" => "t", "OPENROUTER_API_KEY" => nil) do
      assert SystemOneAgent.configured?
      assert_equal :typesafe_direct, SystemOneAgent.preferred_transport_name
    end

    with_env("TYPESAFE_API_KEY" => nil, "OPENROUTER_API_KEY" => "o") do
      assert SystemOneAgent.configured?
      assert_equal :openrouter_decisions, SystemOneAgent.preferred_transport_name
    end

    with_env("TYPESAFE_API_KEY" => "t", "OPENROUTER_API_KEY" => "o") do
      assert SystemOneAgent.configured?
      assert_equal :typesafe_direct, SystemOneAgent.preferred_transport_name
    end
  end

  test "the pinned model ids are asserted by name so an upgrade is deliberate" do
    assert_equal "jev-1.13.0", SystemOneAgent::TYPESAFE_MODEL
    assert_equal "typesafe/jev-1.13", SystemOneAgent::OPENROUTER_MODEL
    assert_equal "jev-1.13.0", SystemOneAgent::TypeSafeHttp::MODEL
    assert_equal "typesafe/jev-1.13", SystemOneAgent::OpenRouterDecisionsHttp::MODEL
  end

  # --- what is sent ---------------------------------------------------------

  test "one request carries the model, the state and every question" do
    _, sent = ask({ "intent" => CHOICE, "here" => NOUL })

    assert_equal SystemOneAgent::TYPESAFE_MODEL, sent[:model]
    assert_equal({ "player_action" => "take it" }, sent[:state])
    assert_equal QUESTIONS, sent[:questions]
  end

  test "the outgoing body is byte-identical between transports except the model id" do
    state = { "player_action" => "take the stamp", "valid_intents" => [ "take" ] }
    questions = QUESTIONS
    captured = {}

    capture = ->(name) do
      SystemOneAgent.new(transport: ->(request) { captured[name] = request; body({ "intent" => CHOICE, "here" => NOUL }) })
                    .ask_questions(state: state, questions: questions)
    end

    with_typesafe { capture.call(:typesafe) }
    with_openrouter { capture.call(:openrouter) }

    typesafe = captured.fetch(:typesafe)
    openrouter = captured.fetch(:openrouter)

    assert_equal SystemOneAgent::TYPESAFE_MODEL, typesafe[:model]
    assert_equal SystemOneAgent::OPENROUTER_MODEL, openrouter[:model]
    assert_equal typesafe.except(:model), openrouter.except(:model),
                 "state and questions must be byte-identical; only the model id may differ"
  end

  test "a request with no questions is not sent at all" do
    assert_raises(SystemOneAgent::Unavailable) do
      with_typesafe { SystemOneAgent.new(transport: ->(_) { flunk "sent an empty request" }).ask_questions(state: {}, questions: {}) }
    end
  end

  # --- what comes back, and what is refused ---------------------------------

  test "a choice and a noul are read back by the ids they were asked under" do
    answers, = ask({ "intent" => CHOICE.merge("choice" => "take"), "here" => NOUL.merge("noul" => 0.91) })

    assert_equal "take", answers.choice("intent")
    assert_in_delta 0.91, answers.noul("here"), 0.0001
    assert answers.asked?("intent")
    assert_not answers.asked?("target_take")
  end

  test "both response envelopes pass through the same Answers validation" do
    typesafe_payload = body({ "intent" => CHOICE, "here" => NOUL })
    openrouter_payload = body({ "intent" => CHOICE, "here" => NOUL },
                              model: SystemOneAgent::OPENROUTER_MODEL,
                              extra: { "id" => "gen-test", "provider" => "TypeSafe",
                                       "usage" => { "input_tokens" => 1, "output_tokens" => 1, "cost" => 0.0001 } })

    typesafe = SystemOneAgent::Answers.new(typesafe_payload, QUESTIONS)
    openrouter = SystemOneAgent::Answers.new(openrouter_payload, QUESTIONS)

    assert_equal "take", typesafe.choice("intent")
    assert_equal "take", openrouter.choice("intent")
    assert_in_delta 0.9, typesafe.noul("here"), 0.0001
    assert_in_delta 0.9, openrouter.noul("here"), 0.0001
    assert_equal "gen-test", openrouter.response_id
    assert_equal "TypeSafe", openrouter.provider
    assert_in_delta 0.0001, openrouter.usage["cost"], 0.0000001
    assert_nil typesafe.response_id
    assert_nil typesafe.provider
  end

  test "an answer set missing a question that was sent is refused" do
    error = assert_raises(SystemOneAgent::UnusableAnswerError) do
      ask({ "intent" => CHOICE })
    end

    assert_includes error.message, "here"
  end

  # THE WHOLE POINT OF A CLOSED SET. An option outside the criteria that were
  # sent is not something the engine nulls later; it is refused here, once.
  test "a choice outside the options sent is refused" do
    answers, = ask({ "intent" => CHOICE.merge("choice" => "fly"), "here" => NOUL })

    assert_raises(SystemOneAgent::UnusableAnswerError) { answers.choice("intent") }
  end

  test "an answer of the wrong type is refused" do
    answers, = ask({ "intent" => NOUL, "here" => NOUL })

    assert_raises(SystemOneAgent::UnusableAnswerError) { answers.choice("intent") }
  end

  test "a noul that is not a probability is refused" do
    answers, = ask({ "intent" => CHOICE, "here" => { "type" => "noul", "noul" => "very" } })

    assert_raises(SystemOneAgent::UnusableAnswerError) { answers.noul("here") }
  end

  test "a body that is not a body at all is refused" do
    assert_raises(SystemOneAgent::UnusableAnswerError) do
      with_typesafe { SystemOneAgent.new(transport: ->(_) { "<html>down for maintenance</html>" }).ask_questions(state: {}, questions: QUESTIONS) }
    end
  end

  test "a body with no answers map is refused" do
    assert_raises(SystemOneAgent::UnusableAnswerError) do
      with_typesafe { SystemOneAgent.new(transport: ->(_) { { "error" => "nope" } }).ask_questions(state: {}, questions: QUESTIONS) }
    end
  end

  test "a malformed success cost is refused rather than trusted as provenance" do
    assert_raises(SystemOneAgent::UnusableAnswerError) do
      SystemOneAgent::Answers.new(
        body({ "intent" => CHOICE, "here" => NOUL },
             extra: { "usage" => { "input_tokens" => 1, "output_tokens" => 1, "cost" => "free" } }),
        QUESTIONS)
    end
  end

  # EVERY ONE OF THEM IS THE SAME FAMILY, which is what lets the caller have one
  # rescue and no opinion about the network.
  test "an unusable answer is an unavailable provider" do
    assert_operator SystemOneAgent::UnusableAnswerError, :<, SystemOneAgent::Unavailable
  end

  # --- the transport --------------------------------------------------------

  class Response
    def initialize(code, message, body) = (@code, @message, @body = code, message, body)
    attr_reader :code, :message, :body
    def is_a?(klass) = klass == Net::HTTPSuccess ? @code.start_with?("2") : super
  end

  def over_http(transport_class, response, key_variable:, key:)
    with_env(key_variable => key) do
      Net::HTTP.stub(:start, ->(*_args, **_options, &_block) { response }) do
        transport_class.new.call({ model: transport_class::MODEL })
      end
    end
  end

  # Documented non-success codes for both contracts, plus a malformed success
  # body: every one collapses to Unavailable so the cascade falls through.
  ERROR_CASES = [
    [ "400", "Bad Request" ],
    [ "401", "Unauthorized" ],
    [ "402", "Payment Required" ],
    [ "403", "Forbidden" ],
    [ "404", "Not Found" ],
    [ "413", "Payload Too Large" ],
    [ "422", "Unprocessable Entity" ],
    [ "429", "Too Many Requests" ],
    [ "500", "Internal Server Error" ],
    [ "502", "Bad Gateway" ],
    [ "503", "Service Unavailable" ],
    [ "524", "A Timeout Occurred" ],
    [ "529", "Overloaded" ]
  ].freeze

  test "every documented error code on TypeSafe maps to Unavailable without the body" do
    ERROR_CASES.each do |code, message|
      error = assert_raises(SystemOneAgent::Unavailable) do
        over_http(SystemOneAgent::TypeSafeHttp, Response.new(code, message, "{\"key\":\"sk-live-secret\"}"),
                  key_variable: "TYPESAFE_API_KEY", key: "sk-live-secret")
      end

      assert_includes error.message, code
      assert_not_includes error.message, "sk-live-secret"
    end
  end

  test "every documented error code on OpenRouter maps to Unavailable without the body" do
    ERROR_CASES.each do |code, message|
      error = assert_raises(SystemOneAgent::Unavailable) do
        over_http(SystemOneAgent::OpenRouterDecisionsHttp, Response.new(code, message, "{\"error\":{\"message\":\"sk-or-secret\"}}"),
                  key_variable: "OPENROUTER_API_KEY", key: "sk-or-secret")
      end

      assert_includes error.message, code
      assert_not_includes error.message, "sk-or-secret"
    end
  end

  test "a body that is not JSON is an unusable answer on either transport" do
    assert_raises(SystemOneAgent::UnusableAnswerError) do
      over_http(SystemOneAgent::TypeSafeHttp, Response.new("200", "OK", "not json"),
                key_variable: "TYPESAFE_API_KEY", key: "k")
    end
    assert_raises(SystemOneAgent::UnusableAnswerError) do
      over_http(SystemOneAgent::OpenRouterDecisionsHttp, Response.new("200", "OK", "not json"),
                key_variable: "OPENROUTER_API_KEY", key: "k")
    end
  end

  test "a timeout is an unavailable provider and nothing louder" do
    error = with_typesafe do
      Net::HTTP.stub(:start, ->(*_args, **_options, &_block) { raise Net::ReadTimeout }) do
        assert_raises(SystemOneAgent::Unavailable) { SystemOneAgent::TypeSafeHttp.new.call({}) }
      end
    end

    assert_includes error.message, "Net::ReadTimeout"
    assert_not_includes error.message, "a-test-typesafe-key"
  end

  test "the credential never appears in an Unavailable message" do
    secret = "sk-live-must-never-leak"
    error = assert_raises(SystemOneAgent::Unavailable) do
      over_http(SystemOneAgent::TypeSafeHttp, Response.new("401", "Unauthorized", "{\"detail\":\"#{secret}\"}"),
                key_variable: "TYPESAFE_API_KEY", key: secret)
    end

    assert_not_includes error.message, secret
    assert_not_includes error.inspect, secret
  end

  # The player is waiting on narration behind this call, so the wait is bounded
  # on both ends: a provider that accepts a connection and says nothing is the
  # failure a read timeout exists for.
  test "the wait is bounded" do
    assert_operator SystemOneAgent::TIMEOUT, :>, 0
    assert_operator SystemOneAgent::TIMEOUT, :<=, 10
  end

  test "OpenRouter's published context ceiling is recorded beside the pin" do
    assert_equal 32_000, SystemOneAgent::OPENROUTER_CONTEXT_CEILING
  end
end
