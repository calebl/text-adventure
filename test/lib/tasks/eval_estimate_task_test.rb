require "test_helper"
require "open3"

# `rake eval:estimate` IN A PROCESS OF ITS OWN, because that is the only place
# its defect showed. RubyLLM 2 defines `RubyLLM::ActiveRecord::Model` in an
# `on_load(:active_record)` hook, and a rake task that asks the registry for a
# price before any record is loaded named a constant that did not exist yet.
# Inside the suite `ActiveRecord::Base` is loaded long before any test runs, so
# the same call in this process passes whether the defect is there or not.
#
# No key and no network: both credentials are removed from the child, and every
# estimate is priced from the registry table alone -- filled from the registry
# the gem ships, in a scratch database of its own so the suite's stays as it was.
#
# THE SCRATCH DATABASE IS LOADED FROM THE SCHEMA, NOT COPIED. A copy of this
# worker's test database was the first version, and it failed now and then in
# CI: the worker's file is in WAL mode, so a plain file copy can miss pages not
# yet checkpointed into it, and it carries whatever registry rows other tests
# in the worker left committed. The registry is saved from the bundled file
# explicitly for the same reason -- `RubyLLM.models` prefers a store over the
# bundle -- and the child checks a bench's model is priced before any estimate
# runs, so a seeding fault is named as one rather than as a bench's error.
class EvalEstimateTaskTest < ActiveSupport::TestCase
  test "every bench's estimate prints without a key" do
    Dir.mktmpdir do |dir|
      database = File.join(dir, "estimate.sqlite3")
      env = { "RAILS_ENV" => "test", "DATABASE_URL" => "sqlite3:#{database}",
              "OPENROUTER_API_KEY" => nil, "TYPESAFE_API_KEY" => nil, "CI" => nil }

      out, status = rails(env, "db:schema:load")
      assert status.success?, out

      out, status = rails(env, "runner", SEED)
      assert status.success?, out

      out, status = rails(env, "eval:estimate")
      assert status.success?, out
      assert_estimates out
    end
  end

  SEED = <<~RUBY.freeze
    RubyLLM::ActiveRecord::Model.save_to_database(RubyLLM::Models.new(RubyLLM::Models.models_from_bundle))
    price = Eval::Cost.price(Eval::Arrival.model)
    abort "the bundled registry has no price for \#{Eval::Arrival.model}" unless price.input_per_million.positive?
  RUBY

  private

  def rails(env, *args)
    Open3.capture2e(env, Rails.root.join("bin/rails").to_s, *args, chdir: Rails.root.to_s)
  end

  def assert_estimates(out)
    [ "Arrival baseline:", "THE BENCHES", "eval:realization", "DIALOGUE", "eval:genesis", "Inscription:", "Narrator branches:" ]
      .each { |line| assert_includes out, line }
  end
end
