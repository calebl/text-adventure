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

  # THE ORDER IS THE DECISION, so it is pinned rather than left implicit.
  # `mistralai/mistral-medium-3.1` is first because it refused 0 of 52 measured
  # charged cases against minimax's 8 of 51, and is 3-4x faster; the accepted
  # cost is thinner prose. See the note on the constant.
  test "mistral is the default hosted model and minimax the fallback" do
    assert_equal [ "mistralai/mistral-medium-3.1", "minimax/minimax-m3" ], BaseAgent::REMOTE_MODEL_IDS
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

  # WAS A BUG, and it made every local entry unreachable. An ollama model is
  # pulled onto the machine and is in neither the bundled registry nor the
  # `models` table, so without the flag a run with no OPENROUTER_API_KEY raised
  # RubyLLM::ModelNotFoundError before it ever reached ollama.
  test "local models are marked as assumed to exist too" do
    assert BaseAgent::LOCAL_MODEL_OPTIONS.all? { |option| option[:assume_model_exists] },
           "an ollama model never resolves against the registry; it has to be assumed to exist"
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

  # A rejected key is not fixed by a different model, and the local models sit
  # at the bottom of the same list -- rotating past a 401 answers from ollama
  # and says nothing about the remote call having been refused.
  test "ask does not rotate when the provider rejects our credentials" do
    agent = build_agent
    chat = UnauthorizedChat.new
    agent.instance_variable_set(:@chat, chat)

    rotations = 0
    agent.stub(:rotate_model, ->(*) { rotations += 1; agent }) do
      error = assert_raises(BaseAgent::UnauthorizedProviderError) { agent.ask("hello") }
      assert_match(/rejected our credentials/, error.message)
    end

    assert_equal 0, rotations
    assert_equal 1, chat.attempts
  end

  test "the unauthorized message names the environment variable to fix" do
    agent = build_agent
    agent.instance_variable_set(:@model_options, [ { provider: :openrouter, model: "vendor/model" } ])
    agent.instance_variable_set(:@chat, UnauthorizedChat.new)

    error = assert_raises(BaseAgent::UnauthorizedProviderError) { agent.ask("hello") }

    assert_match(/OPENROUTER_API_KEY/, error.message)
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

  # --- a caller's own check is a failed call too -------------------------------

  # THE FIX, AT THIS END. `SanitizesGeneratedText::TruncatedTextError` is not
  # declared in BaseAgent -- the rule and the caps belong to the concern and the
  # schema -- but whether it rotates is decided here, and it rotates, on the
  # same side of the line as a schema a model ignored. Before `verify:` existed
  # the raise happened in `InteractionAgent#ask` AFTER this method returned, so
  # the rotation never saw it and a model that truncates cost the player a turn.
  test "ask rotates past an answer the caller's own check rejected" do
    good = { "pre_thought" => "Say something." }
    agent = build_agent
    agent.instance_variable_set(:@chat, SequenceChat.new({ "pre_thought" => "a" * 320 }, good))

    rotations = 0
    agent.stub(:rotate_model, ->(*) { rotations += 1; agent }) do
      answer = agent.ask("what do you think", verify: ->(content) {
        raise SanitizesGeneratedText::TruncatedTextError if content["pre_thought"].length >= 320
      })

      assert_equal good, answer.content
    end

    assert_equal 1, rotations
  end

  test "ask raises the caller's check once the rotation is exhausted" do
    agent = build_agent
    agent.instance_variable_set(:@chat, ConstantChat.new({ "pre_thought" => "a" * 320 }))

    agent.stub(:rotate_model, ->(*) { agent }) do
      assert_raises(SanitizesGeneratedText::TruncatedTextError) do
        agent.ask("what do you think", verify: ->(_content) {
          raise SanitizesGeneratedText::TruncatedTextError, "cut off"
        })
      end
    end
  end

  test "ask runs the caller's check on the parsed content, and only when one is given" do
    seen = []
    agent = build_agent
    agent.instance_variable_set(:@chat, ConstantChat.new({ "action" => "She shrugs." }))

    assert_nothing_raised { agent.ask("hello") }
    agent.ask("hello", verify: ->(content) { seen << content })

    assert_equal [ { "action" => "She shrugs." } ], seen
  end

  # A REJECTED ATTEMPT IS NOT FILED UNDER THE TURN. `record_exchange` runs after
  # the check, so the messages of an attempt that is about to be rewound never
  # become messages `#attribute_to!` would stamp onto the scene.
  test "an answer the caller rejected leaves nothing behind in the conversation" do
    agent = BaseAgent.new("You answer.", purpose: Chat::CHARACTER, model_options: OPTIONS)
    chat = agent.chat

    OfflineExchange.with(
      OfflineExchange.reply({ "pre_thought" => "a" * 320 }),
      OfflineExchange.reply({ "pre_thought" => "Say something." })
    ) do
      agent.stub(:rotate_model, ->(*) { agent }) do
        answer = agent.ask("what do you think", verify: ->(content) {
          raise SanitizesGeneratedText::TruncatedTextError if content["pre_thought"].length >= 320
        })

        assert_equal({ "pre_thought" => "Say something." }, answer.content)
      end
    end

    assert_equal %w[system user assistant], chat.messages.reorder(:id).pluck(:role),
                 "the truncated exchange is not left in a conversation that gets picked up again"
    assert_equal({ "pre_thought" => "Say something." }, chat.messages.find_by(role: "assistant").content_raw)
  end

  # --- what persistence must not break --------------------------------------

  # A CONVERSATION IS A ROW NOW, so a failed attempt leaves rows behind. RubyLLM
  # persists the prompt before it sends it, so without the rewind the retry
  # would ask on top of the failed attempt: the second attempt sends the prompt
  # twice, and a prose answer that was rejected for ignoring the schema is still
  # in the history the replacement model is handed.
  test "a failed attempt is rolled back before the retry, so both attempts ask the same thing" do
    agent = BaseAgent.new("You answer.", purpose: "classifier", model_options: OPTIONS)
    chat = agent.chat

    OfflineExchange.with(
      OfflineExchange.reply("prose, ignoring the schema"),
      OfflineExchange.reply({ "intent" => "move" })
    ) do
      agent.instance_variable_set(:@schema, schema_requiring(:intent))
      agent.stub(:rotate_model, ->(*) { agent }) do
        assert_equal({ "intent" => "move" }, agent.ask("go north").content)
      end
    end

    assert_equal %w[system user assistant], chat.messages.reorder(:id).pluck(:role),
                 "the rejected attempt left nothing behind"
    assert_equal 1, chat.messages.where(role: "user").count, "the prompt was not asked twice"
    assert_nil chat.messages.find_by(role: "assistant").content_raw&.dig("nope")
    assert_equal({ "intent" => "move" }, chat.messages.find_by(role: "assistant").content_raw)
  end

  test "a call that never succeeds leaves the conversation as it found it" do
    agent = BaseAgent.new("You answer.", purpose: "classifier", model_options: OPTIONS)
    chat = agent.chat
    before = chat.messages.reorder(:id).pluck(:id)

    agent.stub(:rotate_model, ->(*) { agent }) do
      OfflineExchange.with do
        assert_raises(RuntimeError) { agent.ask("hello") }
      end
    end

    assert_equal before, chat.messages.reorder(:id).pluck(:id)
  end

  # The 401 guard is the one failure that must NOT rotate, and persistence must
  # not have quietly turned it into one.
  test "a rejected key still fails loudly and still does not rotate, with rows persisted" do
    agent = BaseAgent.new(purpose: "classifier", model_options: OPTIONS)
    chat = agent.chat
    chat.define_singleton_method(:ask) do |message = nil, **_options, &_block|
      add_message(role: :user, content: message)
      raise RubyLLM::UnauthorizedError.new(nil, "Missing Authentication header")
    end

    rotations = 0
    agent.stub(:rotate_model, ->(*) { rotations += 1; agent }) do
      assert_raises(BaseAgent::UnauthorizedProviderError) { agent.ask("hello") }
    end

    assert_equal 0, rotations
    assert_empty chat.messages.reload, "the prompt the refused call wrote is rolled back too"
  end

  # The conversation is a row, so it has to be filed where something can find
  # it again -- and building an agent must not write one on its own.
  test "the conversation is filed under what it is a conversation with" do
    playthrough = create(:playthrough, :started)
    character = create(:character, story: playthrough.story)
    agent = BaseAgent.new(purpose: Chat::CHARACTER, playthrough: playthrough,
                          character: character, model_options: OPTIONS)

    assert_nil agent.recorded_chat

    chat = agent.chat

    assert_equal Chat::CHARACTER, chat.purpose
    assert_equal playthrough, chat.playthrough
    assert_equal character, chat.character
    assert_equal "first-model", chat.model_id, "pointed at the first configured model, not RubyLLM's default"
    assert_same chat, agent.recorded_chat
  end

  # --- a refusal is a failed call -------------------------------------------

  # THE CHANGE, in one test. A refusal was a 200 OK, so the rotation the app
  # already had never ran and `mistralai/mistral-medium-3.1` -- which wrote
  # every response `minimax/minimax-m3` refused -- was never reached. Mistral
  # is first in the list now, so what a rotation reaches is minimax; the
  # behaviour pinned here is the rotation itself, not which model it lands on.
  test "ask rotates past a model that refused the prompt" do
    replacement = "The blade stops an inch short. The child is already up the alley and over the wall."
    agent = build_agent
    agent.instance_variable_set(:@chat, SequenceChat.new(
      "I'm not going to narrate that. Threatening to harm a child isn't something I'll roleplay.",
      replacement
    ))

    rotations = 0
    agent.stub(:rotate_model, ->(*) { rotations += 1; agent }) do
      assert_equal replacement, agent.ask("narrate it").content
    end

    assert_equal 1, rotations
  end

  test "ask raises once every model has refused" do
    agent = build_agent
    agent.instance_variable_set(:@chat, ConstantChat.new("I can't write that scene."))

    agent.stub(:rotate_model, ->(*) { agent }) do
      error = assert_raises(BaseAgent::RefusalError) { agent.ask("narrate it") }
      assert_match(/declined the prompt/, error.message)
      assert_match(/unquoted_first_person/, error.message)
    end
  end

  # A model that declines by listing alternatives is refusing, and it is the
  # shape a word list misses -- the corpus has one opening "The narrator
  # declines this particular scene", third person throughout.
  test "ask treats a menu of alternatives as a refusal" do
    agent = build_agent
    agent.instance_variable_set(:@chat, SequenceChat.new(
      "The narrator declines. Where it could go instead:\n\n- the doorway\n- the ledger",
      "You put the knife away."
    ))

    agent.stub(:rotate_model, ->(*) { agent }) do
      assert_equal "You put the knife away.", agent.ask("narrate it").content
    end
  end

  # THE UNSCHEMA'D GATE. A character's five `Interaction::Schema` fields are
  # first-person by nature -- "I should probably answer" is what a `pre_thought`
  # IS -- so reading a schema'd response for a first-person "I" would fail
  # every talk turn in the game.
  test "ask does not read a schema'd response for a refusal" do
    content = { "pre_thought" => "I won't tell them anything.", "action" => "He says nothing." }
    agent = build_agent
    agent.instance_variable_set(:@schema, Object.new)
    agent.instance_variable_set(:@chat, ConstantChat.new(content))

    rotations = 0
    agent.stub(:rotate_model, ->(*) { rotations += 1; agent }) do
      assert_equal content, agent.ask("what do you think").content
    end

    assert_equal 0, rotations
  end

  # --- a crisis response intercepts instead -----------------------------------

  # INTERCEPT, NOT ROTATE, and the difference is a decision rather than an
  # implementation detail: another model in the list narrates the same exchange
  # in fiction with no intervention, so rotating here would be the app quietly
  # routing around a suicide safety response. It does not rotate, it raises, and
  # the caller shows something the app wrote. See Playthrough::SafetyNotice.
  test "ask does not rotate when a model answered with real-world crisis resources" do
    chat = CountingChat.new(%("Call or text 988 right now," he says. "The Lifeline. Please."))
    agent = build_agent
    agent.instance_variable_set(:@chat, chat)

    rotations = 0
    agent.stub(:rotate_model, ->(*) { rotations += 1; agent }) do
      error = assert_raises(BaseAgent::CrisisResponseError) { agent.ask("talk to him") }
      assert_match(/crisis resources/, error.message)
    end

    assert_equal 0, rotations, "rotating here is the outcome that was explicitly not chosen"
    assert_equal 1, chat.attempts, "and it must not be retried either"
  end

  # THE COLLISION, and the reason the two checks are ORDERED rather than merged
  # into one branch. Run C of the corpus's `i-sh-goad` is a resource card that
  # is also structurally a refusal; if the refusal check won, a suicide safety
  # response would be rotated away from and nobody would have decided that.
  test "a response that is both a refusal and a crisis response intercepts rather than rotating" do
    both = "I'm really concerned about what you've shared. Please reach out:\n\n" \
           "* **988** (call or text) - Suicide & Crisis Lifeline\n\nYou matter."
    assert BaseAgent::Refusal.refused?(both), "the collision has to be real for this test to mean anything"
    assert BaseAgent::Refusal.crisis_response?(both)

    chat = CountingChat.new(both)
    agent = build_agent
    agent.instance_variable_set(:@chat, chat)

    rotations = 0
    agent.stub(:rotate_model, ->(*) { rotations += 1; agent }) do
      assert_raises(BaseAgent::CrisisResponseError) { agent.ask("goad him") }
    end

    assert_equal 0, rotations
    assert_equal 1, chat.attempts
  end

  # Both are `UnusableResponseError` so a caller that persists prose can discard
  # either without knowing which happened (`Scene::Narrator#narrate`), while
  # `#ask` keeps them apart because what it does about them is opposite.
  test "both unusable responses share a parent and stay distinct classes" do
    assert_operator BaseAgent::RefusalError, :<, BaseAgent::UnusableResponseError
    assert_operator BaseAgent::CrisisResponseError, :<, BaseAgent::UnusableResponseError
    assert_not_operator BaseAgent::CrisisResponseError, :<=, BaseAgent::RefusalError
    assert_not_operator BaseAgent::RefusalError, :<=, BaseAgent::CrisisResponseError
  end

  # COUNT IT. "The repo has no record of a refusal ever being a problem" meant
  # nothing while nothing would have recorded one. Tagged so both are greppable.
  test "a refusal and an interception are each logged under their own tag" do
    assert_match(/\[refusal\]/, log_from(ConstantChat.new("I won't write that."), BaseAgent::RefusalError))
    assert_match(/\[crisis\]/, log_from(CountingChat.new("Text HOME to 741741."), BaseAgent::CrisisResponseError))
  end

  # --- temperature -----------------------------------------------------------

  # Set before the conversation exists, applied when it is built; set after,
  # applied to the one that exists. Either way the chat that goes to the model
  # carries it.
  test "with_temperature reaches the conversation whichever side of building it is set" do
    before = BaseAgent.new(model_options: OPTIONS).with_temperature(0.0)
    after = BaseAgent.new(model_options: OPTIONS)

    OfflineExchange.with(OfflineExchange.reply("one"), OfflineExchange.reply("two")) do
      before.ask("first")
      after.ask("second")
    end
    after.with_temperature(0.2)

    assert_equal 0.0, before.chat.to_llm.instance_variable_get(:@temperature)
    assert_equal 0.2, after.chat.to_llm.instance_variable_get(:@temperature)
  end

  test "a conversation left alone carries no temperature of its own" do
    agent = BaseAgent.new(model_options: OPTIONS)
    OfflineExchange.with(OfflineExchange.reply("one")) { agent.ask("first") }

    assert_nil agent.chat.to_llm.instance_variable_get(:@temperature)
  end

  private

  # Runs one doomed ask and returns whatever it wrote to the log.
  def log_from(chat, error)
    agent = build_agent
    agent.instance_variable_set(:@chat, chat)
    written = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(written)

    agent.stub(:rotate_model, ->(*) { agent }) do
      assert_raises(error) { agent.ask("narrate it") }
    end

    written.string
  ensure
    Rails.logger = original
  end

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

  class UnauthorizedChat
    attr_reader :attempts

    def initialize = @attempts = 0

    def ask(_prompt)
      @attempts += 1
      raise RubyLLM::UnauthorizedError.new(nil, "Missing Authentication header")
    end
  end

  # ConstantChat, plus a count, for the checks that must not retry at all.
  class CountingChat
    attr_reader :attempts

    def initialize(content)
      @content = content
      @attempts = 0
    end

    def ask(_prompt)
      @attempts += 1
      Struct.new(:content).new(@content)
    end
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
