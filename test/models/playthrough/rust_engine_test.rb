require "test_helper"

# `Playthrough::RustEngine` is what Ruby knows about the Rust engine: which
# engine plays, when a turn cannot be handed to it, where its model calls go,
# how a failure is counted, and which exception an engine turn ended in. None
# of it needs the extension built; `test/lib/rust_engine_extension_test.rb` is
# what runs against the real one.
class Playthrough::RustEngineTest < ActiveSupport::TestCase
  test "the Rust engine plays unless a block asks for the Ruby reference" do
    Playthrough::RustEngine.using(:rust) do
      assert_equal :rust, Playthrough::RustEngine.engine
      Playthrough::RustEngine.using(:ruby) { assert_equal :ruby, Playthrough::RustEngine.engine }
    end
    # The suite's own default, set once in test_helper.
    assert_equal :ruby, Playthrough::RustEngine.engine
    assert_raises(ArgumentError) { Playthrough::RustEngine.using(:python) { nil } }
  end

  test "the Ruby reference cannot be made the default outside the test environment" do
    Rails.env.stub(:test?, false) do
      assert_raises(Playthrough::RustEngine::EngineError) { Playthrough::RustEngine.reference_by_default! }
    end
  end

  test "a missing extension is an error in words, never a load error" do
    Playthrough::RustEngine.stub(:extension, nil) do
      error = Playthrough::RustEngine.unplayable

      assert_equal "not_built", error.kind
      assert_match "bin/rails engine:build", error.notice
    end
  end

  test "an open transaction is an error too: the engine writes on a connection of its own" do
    Playthrough::RustEngine.stub(:extension, Module.new) do
      # Every test here runs inside a transaction, which is exactly the case.
      assert_equal "transaction_open", Playthrough::RustEngine.unplayable.kind
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

  test "a turn the engine could not play is logged, counted and published, and says nothing of a key" do
    events = []
    subscriber = ActiveSupport::Notifications.subscribe("failure.rust_engine") { |*, payload| events << payload }
    log = StringIO.new
    before = Playthrough::RustEngine.failures.fetch("unsupported", 0)
    error = Playthrough::RustEngine::EngineError.new(:unsupported, "this engine does not play an offer yet")
    with_env("OPENROUTER_API_KEY" => "sk-or-secret") do
      with_logger(Logger.new(log)) { Playthrough::RustEngine.failed!(error) }
    end

    assert_equal before + 1, Playthrough::RustEngine.failures.fetch("unsupported")
    assert_equal [ { kind: "unsupported", message: "this engine does not play an offer yet" } ], events
    assert_match "a turn failed (unsupported): this engine does not play an offer yet", log.string
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
    assert_kind_of Playthrough::RustEngine::EngineError, raised.call("unsupported")
    assert_equal "The engine could not play that turn: m", Playthrough::Session.ending_for(raised.call("panicked")).error
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
