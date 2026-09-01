ENV["RAILS_ENV"] ||= "test"

# THE SUITE RUNS IN A DECLARED ENVIRONMENT, not in whoever's shell started it.
# Every one of these changes how the app behaves, all five are things a person
# working on this app legitimately has in `.env` or `.envrc`, and a test that
# reads one is asserting against a value it did not author:
#
#   OPENROUTER_API_KEY         `BaseAgent.default_model_options` puts the hosted
#                              models first when it is present, so tests that
#                              pin the answering model to a local one fail, and
#                              `RubyLLM.config.openrouter_api_key` is set from
#                              it at boot, so a test expecting an unconfigured
#                              provider to raise gets no exception. Three tests
#                              failed exactly this way for a worker with a key
#                              in their shell.
#   OPENROUTER_MODEL           prepended to `REMOTE_MODEL_IDS`.
#   TA_DEBUG_VIEW              `Playthrough::Debug.enabled?` obeys it in either
#                              direction, so `TA_DEBUG_VIEW=0` turns the whole
#                              debug view off and every test of it red.
#   TA_CHAT_KEEP_TURNS         both are read into `Chat` constants at class-load
#   TA_CHAT_HISTORY_EXCHANGES  time, which is why this is BEFORE the require.
#
# A test that wants one of these sets it itself and puts it back -- see
# `BaseAgentTest#with_env` and `Playthrough::DebugTest#with_env`.
%w[
  OPENROUTER_API_KEY OPENROUTER_MODEL TA_DEBUG_VIEW
  TA_CHAT_KEEP_TURNS TA_CHAT_HISTORY_EXCHANGES
].each { |key| ENV.delete(key) }

require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require_relative "support/fake_agent"
require_relative "support/schema_assertions"
require_relative "support/offline_exchange"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Include FactoryBot methods
    include FactoryBot::Syntax::Methods

    # RubyLLM's model registry is a process-wide memoized snapshot:
    # `RubyLLM::Models.instance` is built once, out of the `models` table, and
    # falls back to the registry JSON the gem ships only when that table is
    # empty. Tests create registry rows inside transactions that roll back, so
    # whichever test touches `RubyLLM.models` first freezes the registry for
    # every test after it in the same process -- and if it did so while the
    # table held only its own rows, later tests resolving a different model
    # name get a ModelNotFoundError for a row they just created. That made
    # model resolution depend on test order and on which parallel worker a test
    # landed in.
    #
    # Dropping the memo before each test makes every test resolve against the
    # rows it created itself. The registry reloads lazily, so a test that never
    # resolves a model pays nothing for this.
    setup { RubyLLM::Models.instance_variable_set(:@instance, nil) }

    # Add more helper methods to be used by all tests here...
  end
end
