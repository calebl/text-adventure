require "test_helper"

class BaseAgentTest < ActiveSupport::TestCase
  OPTIONS = [
    { provider: :ollama, model: "first-model", assume_model_exists: true },
    { provider: :ollama, model: "second-model", assume_model_exists: true },
    { provider: :ollama, model: "third-model", assume_model_exists: true }
  ].freeze

  # Every locally configured model must actually be pullable by name -- the
  # original list pointed at models that were not installed, which surfaced
  # downstream as unreliable generation rather than as a missing model.
  test "local model options are all distinct" do
    models = BaseAgent::LOCAL_MODEL_OPTIONS.map { |option| option[:model] }

    assert_equal models.uniq, models
    assert_predicate models, :any?
  end

  test "prefers remote models when an OpenRouter key is present" do
    with_env("OPENROUTER_API_KEY" => "sk-test") do
      first = BaseAgent.default_model_options.first

      assert_equal :openrouter, first[:provider]
      assert_equal BaseAgent.remote_model_options.count + BaseAgent::LOCAL_MODEL_OPTIONS.count,
                   BaseAgent.default_model_options.count
    end
  end

  test "uses the configured remote models in order" do
    with_env("OPENROUTER_MODEL" => nil) do
      assert_equal BaseAgent::REMOTE_MODEL_IDS, BaseAgent.remote_model_options.map { |option| option[:model] }
    end
  end

  test "configures a fallback so a single bad model does not stop generation" do
    assert_operator BaseAgent::REMOTE_MODEL_IDS.count, :>, 1
  end

  # OpenRouter's `:free` endpoints accept a schema and answer in prose. None of
  # them belong in the default list -- see BaseAgent#verify_schema_honored!.
  test "no free endpoints are configured as defaults" do
    assert_empty BaseAgent::REMOTE_MODEL_IDS.select { |id| id.end_with?(":free") }
  end

  test "OPENROUTER_MODEL takes precedence" do
    with_env("OPENROUTER_MODEL" => "vendor/override") do
      assert_equal "vendor/override", BaseAgent.remote_model_options.first[:model]
    end
  end

  test "OPENROUTER_MODEL is not duplicated when it names a configured model" do
    with_env("OPENROUTER_MODEL" => BaseAgent::REMOTE_MODEL_IDS.last) do
      ids = BaseAgent.remote_model_options.map { |option| option[:model] }

      assert_equal BaseAgent::REMOTE_MODEL_IDS.last, ids.first
      assert_equal ids.uniq, ids
    end
  end

  test "remote models are marked as assumed to exist so no registry lookup happens" do
    with_env("OPENROUTER_MODEL" => nil) do
      assert BaseAgent.remote_model_options.all? { |option| option[:assume_model_exists] }
    end
  end

  test "uses only local models without an OpenRouter key" do
    with_env("OPENROUTER_API_KEY" => nil) do
      assert_equal BaseAgent::LOCAL_MODEL_OPTIONS, BaseAgent.default_model_options
    end
  end

  test "treats a blank OpenRouter key as absent" do
    with_env("OPENROUTER_API_KEY" => "") do
      assert_equal BaseAgent::LOCAL_MODEL_OPTIONS, BaseAgent.default_model_options
    end
  end

  test "starts on the first configured model" do
    agent = build_agent

    assert_equal "first-model", agent.current_model[:model]
  end

  test "rotate_model advances through the options and wraps around" do
    agent = build_agent

    assert_equal "second-model", agent.rotate_model.current_model[:model]
    assert_equal "third-model", agent.rotate_model.current_model[:model]
    assert_equal "first-model", agent.rotate_model.current_model[:model]
  end

  test "rotate_model returns self so it can be chained" do
    agent = build_agent

    assert_same agent, agent.rotate_model
  end

  # RubyLLM::Chat#with_model takes the id positionally and spells the flag
  # `assume_exists`, so the MODEL_OPTIONS hash cannot be splatted into it.
  test "with_model translates option keys for RubyLLM" do
    agent = build_agent
    chat = RecordingChat.new
    agent.instance_variable_set(:@chat, chat)

    agent.with_model(provider: :openrouter, model: "vendor/model", assume_model_exists: true)

    assert_equal [ "vendor/model", { provider: :openrouter, assume_exists: true } ], chat.with_model_call
  end

  test "ask rotates to the next model and retries when a call fails" do
    agent = build_agent
    chat = FlakyChat.new(failures: 1, content: "recovered")
    agent.instance_variable_set(:@chat, chat)
    agent.stub(:rotate_model, ->(*) { agent }) do
      assert_equal "recovered", agent.ask("hello").content
    end

    assert_equal 2, chat.attempts
  end

  test "ask raises once the attempts are exhausted" do
    agent = build_agent
    chat = FlakyChat.new(failures: 99)
    agent.instance_variable_set(:@chat, chat)

    agent.stub(:rotate_model, ->(*) { agent }) do
      assert_raises(RubyLLM::Error) { agent.ask("hello") }
    end

    assert_equal BaseAgent::MAX_ATTEMPTS, chat.attempts
  end

  # A model that accepts a schema and answers in prose is worse than one that
  # fails: `content["field"]` on a String returns a substring, not nil.
  test "ask rejects a prose response when a schema was requested" do
    agent = build_agent
    agent.instance_variable_set(:@chat, ConstantChat.new("# A Dockworker\n\nSome prose."))
    agent.instance_variable_set(:@schema, Object.new)

    agent.stub(:rotate_model, ->(*) { agent }) do
      assert_raises(BaseAgent::SchemaIgnoredError) { agent.ask("hello") }
    end
  end

  test "ask rejects a hash missing required schema fields" do
    agent = build_agent
    agent.instance_variable_set(:@chat, ConstantChat.new({ "physics" => "tides" }))
    agent.instance_variable_set(:@schema, schema_requiring(:physics, :technology, :weapons))

    agent.stub(:rotate_model, ->(*) { agent }) do
      error = assert_raises(BaseAgent::SchemaIgnoredError) { agent.ask("hello") }
      assert_match(/technology/, error.message)
      assert_match(/weapons/, error.message)
      assert_no_match(/physics/, error.message)
    end
  end

  test "ask rejects a hash whose fields came back blank" do
    agent = build_agent
    agent.instance_variable_set(:@chat, ConstantChat.new({ "physics" => "tides", "technology" => "  " }))
    agent.instance_variable_set(:@schema, schema_requiring(:physics, :technology))

    agent.stub(:rotate_model, ->(*) { agent }) do
      assert_raises(BaseAgent::SchemaIgnoredError) { agent.ask("hello") }
    end
  end

  test "ask accepts a hash with every required field present" do
    agent = build_agent
    content = { "physics" => "tides", "technology" => "pumps" }
    agent.instance_variable_set(:@chat, ConstantChat.new(content))
    agent.instance_variable_set(:@schema, schema_requiring(:physics, :technology))

    assert_equal content, agent.ask("hello").content
  end

  test "ask accepts a schema that does not expose required properties" do
    agent = build_agent
    agent.instance_variable_set(:@chat, ConstantChat.new({ "anything" => "goes" }))
    agent.instance_variable_set(:@schema, Object.new)

    assert_equal({ "anything" => "goes" }, agent.ask("hello").content)
  end

  test "ask accepts a hash response when a schema was requested" do
    agent = build_agent
    agent.instance_variable_set(:@chat, ConstantChat.new({ "name" => "Silas" }))
    agent.instance_variable_set(:@schema, Object.new)

    assert_equal({ "name" => "Silas" }, agent.ask("hello").content)
  end

  test "ask leaves prose alone when no schema was requested" do
    agent = build_agent
    agent.instance_variable_set(:@chat, ConstantChat.new("just prose"))

    assert_equal "just prose", agent.ask("hello").content
  end

  test "ask rotates past a model that ignores the schema" do
    agent = build_agent
    agent.instance_variable_set(:@schema, Object.new)
    agent.instance_variable_set(:@chat, SequenceChat.new("prose", { "name" => "Silas" }))

    rotations = 0
    agent.stub(:rotate_model, ->(*) { rotations += 1; agent }) do
      assert_equal({ "name" => "Silas" }, agent.ask("hello").content)
    end

    assert_equal 1, rotations
  end

  private

  def build_agent
    BaseAgent.new(model_options: OPTIONS)
  end

  def schema_requiring(*keys)
    Struct.new(:required_properties).new(keys)
  end

  def with_env(values)
    original = values.transform_values { |_| nil }
    values.each_key { |key| original[key] = ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| ENV[key] = value }
  end

  class RecordingChat
    attr_reader :with_model_call

    def with_model(model, **options)
      @with_model_call = [ model, options ]
      self
    end
  end

  class ConstantChat
    def initialize(content) = @content = content
    def ask(_prompt) = Struct.new(:content).new(@content)
  end

  class SequenceChat
    def initialize(*contents) = @contents = contents
    def ask(_prompt) = Struct.new(:content).new(@contents.shift)
  end

  class FlakyChat
    attr_reader :attempts

    def initialize(failures:, content: "ok")
      @failures = failures
      @content = content
      @attempts = 0
    end

    def ask(_prompt)
      @attempts += 1
      raise RubyLLM::Error.new(nil, "boom") if @attempts <= @failures

      Struct.new(:content).new(@content)
    end
  end
end
