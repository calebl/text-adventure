require "test_helper"

# `Playthrough::RustEngine` is the switch and what Ruby knows about the Rust
# engine: when a turn may be handed over, where its model calls go, how a
# fallback is counted, and which Ruby exception an engine turn ended in. None of
# it needs the extension built; `test/lib/rust_engine_extension_test.rb` is
# what runs against the real one.
class Playthrough::RustEngineTest < ActiveSupport::TestCase
  test "the switch is the environment variable, and a thread may set it either way" do
    with_env("TA_ENGINE" => nil) { assert_not Playthrough::RustEngine.wanted? }
    with_env("TA_ENGINE" => "ruby") { assert_not Playthrough::RustEngine.wanted? }
    with_env("TA_ENGINE" => " Rust ") do
      assert Playthrough::RustEngine.wanted?
      Playthrough::RustEngine.using(:ruby) { assert_not Playthrough::RustEngine.wanted? }
    end
    Playthrough::RustEngine.using(:rust) { assert Playthrough::RustEngine.wanted? }
    assert_raises(ArgumentError) { Playthrough::RustEngine.using(:python) { nil } }
  end

  test "a missing extension is nil with its reason kept, never an exception" do
    Playthrough::RustEngine.stub(:extension, nil) do
      assert_equal :not_built, Playthrough::RustEngine.unplayable("token")
    end
  end

  test "a turn is handed over only with a token, the extension, no local models and no open transaction" do
    Playthrough::RustEngine.stub(:extension, Module.new) do
      assert_equal :no_request_token, Playthrough::RustEngine.unplayable(nil)
      with_env("TA_LOCAL_MODELS" => "1") { assert_equal :local_models, Playthrough::RustEngine.unplayable("token") }
      # Every test here runs inside a transaction, which is exactly the case:
      # the engine could neither write nor see this connection's rows.
      assert_equal :transaction_open, Playthrough::RustEngine.unplayable("token")
    end
  end

  test "the model calls go where Ruby's go: the OpenRouter key as the Direct route" do
    with_env("OPENROUTER_API_KEY" => "sk-or-test", "TYPESAFE_API_KEY" => nil, "OPENROUTER_MODEL" => "some/model") do
      assert_equal({ route: "direct", key: "sk-or-test", model: "some/model", system_one: "decisions", typesafe_key: nil },
                   Playthrough::RustEngine.models)
    end
    with_env("OPENROUTER_API_KEY" => nil, "TYPESAFE_API_KEY" => "ts-test") do
      assert_equal({ route: "none", key: nil, model: nil, system_one: "typesafe", typesafe_key: "ts-test" },
                   Playthrough::RustEngine.models)
    end
    assert_equal({ route: "none", key: nil, model: nil, system_one: "off", typesafe_key: nil },
                 Playthrough::RustEngine.models)
  end

  test "the sweep's guard stops a live models document being built" do
    EngineSweep.without_a_model do
      assert_raises(EngineSweep::ModelCalled) { Playthrough::RustEngine.models }
    end
    assert_nil Playthrough::RustEngine.live_models_guard
  end

  test "a fallback is logged, counted and published, and says nothing of a key" do
    events = []
    subscriber = ActiveSupport::Notifications.subscribe("fallback.rust_engine") { |*, payload| events << payload }
    log = StringIO.new
    before = Playthrough::RustEngine.fallbacks.fetch("unsupported", 0)
    with_env("OPENROUTER_API_KEY" => "sk-or-secret") do
      with_logger(Logger.new(log)) { Playthrough::RustEngine.fell_back!(:unsupported, "an offer through the models") }
    end

    assert_equal before + 1, Playthrough::RustEngine.fallbacks.fetch("unsupported")
    assert_equal [ { reason: "unsupported", detail: "an offer through the models" } ], events
    assert_match "this turn plays on Ruby (unsupported: an offer through the models)", log.string
    assert_no_match "sk-or-secret", log.string
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test "an engine turn ends in the Ruby engine's own exception, so the player is told the same thing" do
    raised = ->(kind, failure = nil) { Playthrough::RustEngine.exception_for("kind" => kind, "failure" => failure, "message" => "m") }

    assert_kind_of BaseAgent::CrisisResponseError, raised.call("model", "crisis")
    assert Playthrough::Session.ending_for(raised.call("model", "crisis")).safety_notice
    assert_kind_of BaseAgent::NoModelConfiguredError, raised.call("model", "no_model")
    assert_equal Playthrough::SetupNotice::UNFINISHED, Playthrough::Session.ending_for(raised.call("model", "no_model")).error
    assert_kind_of BaseAgent::UnauthorizedProviderError, raised.call("model", "unauthorized")
    assert_kind_of BaseAgent::RefusalError, raised.call("model", "refused")
    assert_kind_of BaseAgent::SchemaIgnoredError, raised.call("model", "schema_ignored")
    assert_kind_of Playthrough::RustEngine::ModelFailed, raised.call("model", "provider")
    assert_equal Playthrough::TurnFailureNotice::MESSAGE, Playthrough::Session.ending_for(raised.call("model", "provider")).error
    assert_kind_of Playthrough::RustEngine::ProviderUnavailable, raised.call("model", "unavailable")
    assert_kind_of Playthrough::Command::InterruptedError, raised.call("interrupted")
    assert_kind_of Playthrough::Command::PreviouslyFailedError, raised.call("previously_failed")
    assert_kind_of Interrupt, raised.call("stopped")
  end

  test "the engine errors that hand a turn back are the engine's, never a model's" do
    assert_equal %w[database no_such_playthrough no_such_story panicked schema_changed schema_mismatch unsupported],
                 Playthrough::RustEngine::HANDED_BACK.sort
  end

  private

  def with_env(values)
    saved = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  def with_logger(logger)
    saved = Rails.logger
    Rails.logger = logger
    yield
  ensure
    Rails.logger = saved
  end
end
