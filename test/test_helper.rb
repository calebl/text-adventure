ENV["RAILS_ENV"] ||= "test"

# THE SUITE RUNS IN A DECLARED ENVIRONMENT, not in whoever's shell started it
# and not in whoever's `.env`. Every one of these changes how the app behaves,
# all five are things a person working on this app legitimately has in `.env` or
# `.envrc`, and a test that reads one is asserting against a value it did not
# author:
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
#   TA_CHAT_HISTORY_EXCHANGES  time, which is why the first pass is BEFORE the
#                              require.
#
# It takes TWO passes, and the second one is not belt-and-braces. `dotenv-rails`
# is in the `:development, :test` group, so it loads `.env` while
# `config/environment` boots -- and dotenv declines to override only the keys it
# finds already set. Deleting them beforehand therefore *hands it* the opening
# to put them straight back, which is exactly what it does: with the first pass
# alone, `ENV["OPENROUTER_API_KEY"]` and `RubyLLM.config.openrouter_api_key` are
# both populated again by the time the first test runs, on any checkout with a
# `.env`. Measured, not assumed. So: once before the require, for the constants
# frozen at class-load time, and once after it, for dotenv.
#
# A test that wants one of these sets it itself and puts it back -- see
# `BaseAgentTest#with_env` and `Playthrough::DebugTest#with_env`.
declare_environment = lambda do
  %w[
    OPENROUTER_API_KEY OPENROUTER_MODEL TA_DEBUG_VIEW
    TA_CHAT_KEEP_TURNS TA_CHAT_HISTORY_EXCHANGES
  ].each { |key| ENV.delete(key) }
end

declare_environment.call
require_relative "../config/environment"
declare_environment.call

# And the copy the initializer already took, because `config/initializers/ruby_llm.rb`
# ran during that require. A test that wants a key configured sets it on
# `RubyLLM.config` itself and restores it (see `with_openrouter_key` in
# `test/models/chat_test.rb`).
RubyLLM.config.openrouter_api_key = nil

require "rails/test_help"
require "minitest/mock"
require_relative "support/fake_agent"
require_relative "support/schema_assertions"
require_relative "support/offline_exchange"
require_relative "support/refusal_corpus_skeleton"

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

    # A THING ON THE FLOOR OF A ROOM, IN ONE GAME -- the world's own row and this
    # playthrough's copy of it, taken the way the turn loop takes it.
    #
    # Since the captain's ruling of 2026-09-04 the closed set `take` resolves
    # against is the PLAYTHROUGH layer (`Playthrough#items_lying_in`), and
    # `create(:item, :lying, ...)` writes the WORLD layer -- the template a game
    # copies from. A test that wrote only the template would be asserting
    # against a room this party has never seen. So this writes the template and
    # then calls `Item::Snapshot`, which is the same statement
    # `Playthrough::Turn#play` and `#move_to` make, and returns the copy the
    # loop will actually resolve.
    def lying_here(playthrough, location, *traits, **attributes)
      create(:item, :lying, *traits, location: location, **attributes)
      Item::Snapshot.new(playthrough).of_the_room!(location)
      playthrough.items_lying_in(location).order(:id).last
    end

    # Add more helper methods to be used by all tests here...
  end
end
