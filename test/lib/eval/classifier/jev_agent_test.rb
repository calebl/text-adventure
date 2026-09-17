require "test_helper"

class Eval::Classifier::JevAgentTest < ActiveSupport::TestCase
  Record = Data.define(:name)

  class FakeClassifier
    attr_reader :sets

    def initialize(sets = {})
      @sets = sets
    end

    def exits_here = sets.fetch(:move, [])
    def characters_here = sets.fetch(:talk, [])
    def items_here = sets.fetch(:take, [])
    def items_carried = sets.fetch(:drop, [])
    def offered_for(intent) = sets.fetch(intent, [])
    def command_prompt(command, *) = "The player types: #{command}"
  end

  class FakeTransport
    attr_reader :payload, :api_key, :timeout

    def initialize(&answer)
      @answer = answer
    end

    def post(payload, api_key:, timeout:)
      @payload = payload
      @api_key = api_key
      @timeout = timeout
      body = @answer.call(payload)
      Eval::Classifier::JevAgent::TransportReceipt.new(status: 200, request_id: "request-1", body: body)
    end
  end

  test "the live classifier keeps using its BaseAgent route" do
    story = create(:story)
    protagonist = create(:character, story:, is_protagonist: true)
    location = create(:location, story:)
    playthrough = create(:playthrough, story:, character: protagonist, current_location: location)
    agent = FakeAgent.new({ "intent" => "other", "target" => "nothing", "also_named" => "nothing" })

    intent = Eval::Classifier::JevAgent.stub(:new, ->(*) { flunk "live classification reached the Jev adapter" }) do
      BaseAgent.stub(:new, agent) { Playthrough::Classifier.new(playthrough).classify("wait") }
    end

    assert_equal :other, intent.action
  end

  test "one opaque Choice contains complete engine-valid tuples including also_named" do
    hall = Record.new(name: "Hall")
    closet = Record.new(name: "Closet")
    classifier = FakeClassifier.new(move: [ hall, closet ])
    agent = build_agent(classifier)

    options = agent.options_for.values
    tuples = options.map { |option| [ option.intent, option.target, option.also_named ] }

    assert_includes tuples, [ :move, nil, nil ]
    assert_includes tuples, [ :move, "Hall", nil ]
    assert_includes tuples, [ :move, "Closet", nil ]
    assert_includes tuples, [ :move, "Hall", "Closet" ]
    assert_not_includes tuples, [ :talk, "Hall", nil ], "a record cannot leak into an action that never offers it"
    assert agent.options_for.keys.all? { |key| key.match?(/\Achoice_\d{3}\z/) },
           "keys are opaque so only the criteria carry semantics"
  end

  test "it refuses a combinatorial shape above the application option limit before a call" do
    many = (1..12).map { |number| Record.new(name: "Place #{number}") }
    agent = build_agent(FakeClassifier.new(move: many))

    error = assert_raises(Eval::Classifier::JevAgent::TooManyOptions) { agent.options_for }
    assert_match(/limit is 64/, error.message)
  end

  test "it validates a receipt and returns the selected tuple with actual billed usage" do
    hall = Record.new(name: "Hall")
    classifier = FakeClassifier.new(move: [ hall ])
    transport = FakeTransport.new do |payload|
      choices = payload.dig(:questions, :reading, :criteria).keys
      selected = choices.find { |key| payload.dig(:questions, :reading, :criteria, key).include?("exactly the engine-supplied choice `Hall`") }
      response(choices, selected:, confidence: 0.82, input: 2_000, output: 40)
    end
    agent = build_agent(classifier, transport: transport)

    result = agent.classify("go to the hall")

    assert_equal :move, result.answer.intent
    assert_equal "Hall", result.answer.target
    assert_nil result.answer.also_named
    assert_equal 0.82, result.confidence
    assert_equal({ "input_tokens" => 2_000, "output_tokens" => 40 }, result.usage)
    assert_in_delta 0.000084, result.billed_cost
    assert_equal "secret-for-test", transport.api_key
    assert_equal 5, transport.timeout
    assert_equal "request-1", result.receipt.fetch("request_id")
    assert_not_includes JSON.generate(result.request), "secret-for-test",
                        "the exact request receipt must never contain the credential"
  end

  test "a malformed billable response retains its key-free request, receipt, usage and cost" do
    transport = FakeTransport.new do |payload|
      choices = payload.dig(:questions, :reading, :criteria).keys
      response(choices, selected: "not-an-offered-choice", confidence: 0.8, input: 2_000, output: 40)
    end
    agent = build_agent(FakeClassifier.new, transport:)

    assert_raises(Eval::Classifier::JevAgent::MalformedResponse) { agent.classify("wait") }
    assert_equal({ "input_tokens" => 2_000, "output_tokens" => 40 }, agent.recorded_usage)
    assert_in_delta 0.000084, agent.recorded_billed_cost
    assert_equal "request-1", agent.recorded_receipt.fetch("request_id")
    assert_equal "jev-latest", agent.recorded_request.fetch(:model)
    assert_not_includes JSON.generate(agent.recorded_request), "secret-for-test"
  end

  test "malformed usage keeps only safe billable fields without breaking failure accounting" do
    transport = FakeTransport.new do |payload|
      choices = payload.dig(:questions, :reading, :criteria).keys
      body = response(choices, selected: "not-an-offered-choice", confidence: 0.8, input: 700, output: 20)
      body.fetch("usage")["output_tokens"] = "twenty"
      body
    end
    agent = build_agent(FakeClassifier.new, transport:)

    assert_raises(Eval::Classifier::JevAgent::MalformedResponse) { agent.classify("wait") }
    assert_equal({ "input_tokens" => 700 }, agent.recorded_usage)
    assert_in_delta Eval::Classifier::JevAgent::PRICE.of(700, 0), agent.recorded_billed_cost
    assert_equal "twenty", agent.recorded_receipt.dig("body", "usage", "output_tokens"),
                 "the exact malformed provider receipt is preserved even though aggregation rejects its value"
  end

  test "missing key and malformed choice are failures, never coercions" do
    classifier = FakeClassifier.new
    assert_raises(Eval::Classifier::JevAgent::MissingKey) do
      Eval::Classifier::JevAgent.new(classifier:, api_key: "").classify("wait")
    end

    transport = FakeTransport.new { |_payload| { "model" => "jev", "answers" => {}, "usage" => {} } }
    assert_raises(Eval::Classifier::JevAgent::MalformedResponse) do
      build_agent(classifier, transport:).classify("wait")
    end
  end

  test "timeout and no-network errors stay failures for the bench to count" do
    classifier = FakeClassifier.new
    timeout = Object.new
    timeout.define_singleton_method(:post) { |*| raise Net::ReadTimeout }
    offline = Object.new
    offline.define_singleton_method(:post) { |*| raise SocketError, "network unreachable" }

    assert_raises(Net::ReadTimeout) { build_agent(classifier, transport: timeout).classify("wait") }
    assert_raises(SocketError) { build_agent(classifier, transport: offline).classify("wait") }
  end

  private
    def build_agent(classifier, transport: FakeTransport.new { |payload|
      choices = payload.dig(:questions, :reading, :criteria).keys
      response(choices, selected: choices.first, confidence: 1.0)
    })
      Eval::Classifier::JevAgent.new(classifier:, api_key: "secret-for-test", transport:)
    end

    def response(choices, selected:, confidence:, input: 100, output: 10)
      probabilities = choices.index_with { 0.0 }
      probabilities[selected] = confidence
      remainder = 1.0 - confidence
      other = choices.find { |choice| choice != selected }
      probabilities[other] = remainder if other
      {
        "model" => "jev-1.13.0",
        "answers" => {
          "reading" => {
            "type" => "choice", "choice" => selected, "confidence" => confidence,
            "probabilities" => probabilities
          }
        },
        "usage" => { "input_tokens" => input, "output_tokens" => output }
      }
    end
end
