require "test_helper"

# THE PROVIDER BOUNDARY. Two things are worth pinning here and the rest belongs
# to the caller: that an absent key is not an error but an absent cascade, and
# that every way a request can come back unbelievable is ONE error family, so no
# caller is ever invited to branch on the network.
class SystemOneAgentTest < ActiveSupport::TestCase
  # The suite deletes `TYPESAFE_API_KEY` at boot (see `test_helper.rb`), so a
  # test that wants one sets it and puts it back.
  def with_key(value = "a-test-key")
    was = ENV["TYPESAFE_API_KEY"]
    ENV["TYPESAFE_API_KEY"] = value
    yield
  ensure
    ENV["TYPESAFE_API_KEY"] = was
  end

  QUESTIONS = {
    "intent" => { "type" => "choice", "instructions" => "which?", "criteria" => { "take" => "a", "other" => "b" } },
    "here" => { "type" => "noul", "instructions" => "is it?" }
  }.freeze

  def body(answers)
    { "model" => "jev-latest", "answers" => answers, "usage" => { "input_tokens" => 1, "output_tokens" => 1 } }
  end

  def ask(answers, questions: QUESTIONS)
    sent = []
    agent = SystemOneAgent.new(transport: ->(request) { sent << request; body(answers) })
    with_key { [ agent.ask_questions(state: { "player_action" => "take it" }, questions: questions), sent.first ] }
  end

  # --- the key is the switch ------------------------------------------------

  test "the key alone says whether there is a cascade at all" do
    assert_not SystemOneAgent.configured?, "the suite must run keyless by default"
    with_key { assert SystemOneAgent.configured? }
    with_key("") { assert_not SystemOneAgent.configured?, "an empty key is not a key" }
  end

  # An absent key is an ordinary machine, not a broken install -- so it is
  # deliberately NOT `BaseAgent::NoModelConfiguredError`, which names a game
  # with no model at all.
  test "asking with no key is unavailable and never a missing model" do
    error = assert_raises(SystemOneAgent::Unavailable) do
      SystemOneAgent.new(transport: ->(_) { body({}) }).ask_questions(state: {}, questions: QUESTIONS)
    end

    assert_not_kind_of BaseAgent::NoModelConfiguredError, error
    assert_includes error.message, "TYPESAFE_API_KEY"
  end

  # --- what is sent ---------------------------------------------------------

  test "one request carries the model, the state and every question" do
    _, sent = ask({ "intent" => { "type" => "choice", "choice" => "take", "probabilities" => {}, "confidence" => 1.0 },
                  "here" => { "type" => "noul", "noul" => 0.9 } })

    assert_equal SystemOneAgent::MODEL, sent[:model]
    assert_equal({ "player_action" => "take it" }, sent[:state])
    assert_equal QUESTIONS, sent[:questions]
  end

  test "a request with no questions is not sent at all" do
    assert_raises(SystemOneAgent::Unavailable) do
      with_key { SystemOneAgent.new(transport: ->(_) { flunk "sent an empty request" }).ask_questions(state: {}, questions: {}) }
    end
  end

  # --- what comes back, and what is refused ---------------------------------

  test "a choice and a noul are read back by the ids they were asked under" do
    answers, = ask({ "intent" => { "type" => "choice", "choice" => "take", "probabilities" => {}, "confidence" => 1.0 },
                   "here" => { "type" => "noul", "noul" => 0.91 } })

    assert_equal "take", answers.choice("intent")
    assert_in_delta 0.91, answers.noul("here"), 0.0001
    assert answers.asked?("intent")
    assert_not answers.asked?("target_take")
  end

  test "an answer set missing a question that was sent is refused" do
    error = assert_raises(SystemOneAgent::UnusableAnswerError) do
      ask({ "intent" => { "type" => "choice", "choice" => "take", "probabilities" => {}, "confidence" => 1.0 } })
    end

    assert_includes error.message, "here"
  end

  # THE WHOLE POINT OF A CLOSED SET. An option outside the criteria that were
  # sent is not something the engine nulls later; it is refused here, once.
  test "a choice outside the options sent is refused" do
    answers, = ask({ "intent" => { "type" => "choice", "choice" => "fly", "probabilities" => {}, "confidence" => 1.0 },
                   "here" => { "type" => "noul", "noul" => 0.9 } })

    assert_raises(SystemOneAgent::UnusableAnswerError) { answers.choice("intent") }
  end

  test "an answer of the wrong type is refused" do
    answers, = ask({ "intent" => { "type" => "noul", "noul" => 0.4 },
                   "here" => { "type" => "noul", "noul" => 0.9 } })

    assert_raises(SystemOneAgent::UnusableAnswerError) { answers.choice("intent") }
  end

  test "a noul that is not a probability is refused" do
    answers, = ask({ "intent" => { "type" => "choice", "choice" => "take", "probabilities" => {}, "confidence" => 1.0 },
                   "here" => { "type" => "noul", "noul" => "very" } })

    assert_raises(SystemOneAgent::UnusableAnswerError) { answers.noul("here") }
  end

  test "a body that is not a body at all is refused" do
    assert_raises(SystemOneAgent::UnusableAnswerError) do
      with_key { SystemOneAgent.new(transport: ->(_) { "<html>down for maintenance</html>" }).ask_questions(state: {}, questions: QUESTIONS) }
    end
  end

  test "a body with no answers map is refused" do
    assert_raises(SystemOneAgent::UnusableAnswerError) do
      with_key { SystemOneAgent.new(transport: ->(_) { { "error" => "nope" } }).ask_questions(state: {}, questions: QUESTIONS) }
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

  def over_http(response)
    with_key do
      Net::HTTP.stub(:start, ->(*_args, **_options, &_block) { response }) do
        SystemOneAgent::Http.new.call({ model: "jev-latest" })
      end
    end
  end

  test "a refused request names its status and never its body" do
    error = assert_raises(SystemOneAgent::Unavailable) { over_http(Response.new("401", "Unauthorized", "{\"key\":\"sk-live-secret\"}")) }

    assert_includes error.message, "401"
    assert_not_includes error.message, "sk-live-secret"
  end

  test "a body that is not JSON is an unusable answer" do
    assert_raises(SystemOneAgent::UnusableAnswerError) { over_http(Response.new("200", "OK", "not json")) }
  end

  test "a timeout is an unavailable provider and nothing louder" do
    error = with_key do
      Net::HTTP.stub(:start, ->(*_args, **_options, &_block) { raise Net::ReadTimeout }) do
        assert_raises(SystemOneAgent::Unavailable) { SystemOneAgent::Http.new.call({}) }
      end
    end

    assert_includes error.message, "Net::ReadTimeout"
  end

  # The player is waiting on narration behind this call, so the wait is bounded
  # on both ends: a provider that accepts a connection and says nothing is the
  # failure a read timeout exists for.
  test "the wait is bounded" do
    assert_operator SystemOneAgent::TIMEOUT, :>, 0
    assert_operator SystemOneAgent::TIMEOUT, :<=, 10
  end
end
