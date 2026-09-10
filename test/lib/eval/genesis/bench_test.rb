require "test_helper"

class Eval::Genesis::BenchTest < ActiveSupport::TestCase
  Response = Data.define(:content, :input_tokens, :output_tokens, :model_id)
  class FakeChat
    attr_reader :params
    def initialize(response) = @response = response
    def with_params(**params) = @params = params
    def ask(*) = @response
  end
  class FakeAgent
    attr_reader :chat, :history
    def initialize(response, reject: false)
      @chat, @history, @reject = FakeChat.new(response), [], reject
    end
    def with_instructions(*) = self
    def with_schema(*) = self
    def add_message(**message) = @history << message
    def ask(prompt)
      response = chat.ask(prompt)
      raise BaseAgent::SchemaIgnoredError, "bad shape" if @reject
      response
    end
  end

  test "rejected provider output and its tokens survive verification failure" do
    kase = Eval::Genesis.corpus.cases.find { |candidate| candidate.id == "story" }
    response = Response.new(content: { "level" => 900 }, input_tokens: 80, output_tokens: 10,
                            model_id: Eval::Cost.default_model)
    fake = FakeAgent.new(response, reject: true)
    bench = Eval::Genesis::Bench.new(io: nil)
    Eval::Genesis::Stage.open(kase) do |stage|
      BaseAgent.stub(:new, fake) do
        row = bench.read(stage, stage.requests.sole, 1)
        assert_match(/\ABaseAgent::SchemaIgnoredError:/, row["error"])
        assert_equal response.content, row["answer"]
        assert_equal 80, row["input_tokens"]
        assert_equal response.model_id, row["answered_by"]
        assert_operator fake.chat.params[:max_tokens], :>, 0
      end
    end
  end

  test "retry restores both messages and buys only its followup" do
    kase = Eval::Genesis.corpus.cases.find { |candidate| candidate.producer == "retry" }
    Eval::Genesis::Stage.open(kase) do |stage|
      request = stage.requests.sole
      answer = request.history.last.fetch("content").merge("fullname" => "A New Name")
      fake = FakeAgent.new(Response.new(content: answer, input_tokens: 90, output_tokens: 20,
                                        model_id: Eval::Cost.default_model))
      BaseAgent.stub(:new, fake) do
        row = Eval::Genesis::Bench.new(io: nil).read(stage, request, 1)
        assert_nil row["error"]
        assert_equal 2, fake.history.size
        assert_equal request.facts["body"], row.dig("after", "body")
        assert_equal 0.0, Eval::Genesis::Scorer.new([ row ]).rate(:retry_not_distinct)
      end
    end
  end

  test "budget gate fires before any agent is built" do
    kase = Eval::Genesis.corpus.cases.first
    bench = Eval::Genesis::Bench.new(io: nil)
    bench.instance_variable_set(:@reserved, Eval::Genesis::Bench::SPEND_CEILING + 1)
    Eval::Genesis::Stage.open(kase) do |stage|
      BaseAgent.stub(:new, ->(*) { flunk "must not buy a call" }) do
        assert_raises(ArgumentError) { bench.read(stage, stage.requests.first, 1) }
      end
    end
  end
end
