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
# estimate is priced from the registry table alone -- filled, as `db:seed` fills
# it, from the registry the gem ships, in a copy of the test database so the
# suite's own stays as it was.
class EvalEstimateTaskTest < ActiveSupport::TestCase
  test "every bench's estimate prints without a key" do
    Dir.mktmpdir do |dir|
      database = File.join(dir, "estimate.sqlite3")
      FileUtils.cp(ActiveRecord::Base.connection_db_config.database, database)
      env = { "RAILS_ENV" => "test", "DATABASE_URL" => "sqlite3:#{database}",
              "OPENROUTER_API_KEY" => nil, "TYPESAFE_API_KEY" => nil, "CI" => nil }

      _, status = rails(env, "runner", "RubyLLM::ActiveRecord::Model.save_to_database")
      assert status.success?, "the registry could not be loaded into the copy"

      out, status = rails(env, "eval:estimate")
      assert status.success?, out
      assert_estimates out
    end
  end

  private

  def rails(env, *args)
    Open3.capture2e(env, Rails.root.join("bin/rails").to_s, *args, chdir: Rails.root.to_s)
  end

  def assert_estimates(out)
    [ "Arrival baseline:", "THE BENCHES", "eval:realization", "DIALOGUE", "eval:genesis", "Inscription:", "Narrator branches:" ]
      .each { |line| assert_includes out, line }
  end
end
