ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require_relative "support/fake_agent"
require_relative "support/schema_assertions"
require_relative "support/fake_chat"

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
