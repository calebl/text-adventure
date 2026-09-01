require "test_helper"
require Rails.root.join("lib/middleware/stale_schema_guard")

# The middleware is only inserted in development, so this drives it directly.
# What is worth pinning is the judgement in it: it reports and never repairs,
# and it takes its baseline from the first request rather than from boot.
class StaleSchemaGuardTest < ActiveSupport::TestCase
  OK = [ 200, {}, [ "ok" ] ].freeze

  def app(calls = [])
    ->(env) { calls << env; OK }
  end

  test "passes the request through while the schema version holds still" do
    calls = []
    guard = StaleSchemaGuard.new(app(calls), version: -> { 20260831140000 })

    3.times { assert_equal OK, guard.call({}) }

    assert_equal 3, calls.size
  end

  test "refuses the request once the database has been migrated underneath it" do
    versions = [ 20260831130000, 20260831130000, 20260831140000 ]
    calls = []
    guard = StaleSchemaGuard.new(app(calls), version: -> { versions.shift })

    guard.call({})
    guard.call({})
    error = assert_raises(StaleSchemaGuard::StaleSchemaError) { guard.call({}) }

    assert_equal 2, calls.size, "the request that would have failed on a stale column never ran"
    assert_match(/migrated while this server was running/, error.message)
    assert_match(/20260831130000/, error.message)
    assert_match(/20260831140000/, error.message)
    assert_match(/Restart the server/, error.message)
  end

  # The baseline is the FIRST request rather than boot: nothing has cached a
  # column list until something has read a record, so a migration that lands
  # before any request has been served leaves the process perfectly current.
  test "a migration before the first request is not stale" do
    versions = [ 20260831140000, 20260831140000 ]
    guard = StaleSchemaGuard.new(app, version: -> { versions.shift })

    assert_equal OK, guard.call({})
    assert_equal OK, guard.call({})
  end

  test "says nothing when there is no schema to read" do
    guard = StaleSchemaGuard.new(app, version: -> { nil })

    assert_equal OK, guard.call({})
  end

  # It reports; it does not reach into ActiveRecord and try to heal the process.
  # Recovering in place would need the connection's prepared statements dropped
  # as well as the column cache, and a new process is the honest answer.
  test "reads the version through the migration context and nothing else" do
    guard = StaleSchemaGuard.new(app)

    assert_equal ActiveRecord::Base.connection_pool.migration_context.current_version,
                 guard.send(:current_version)
  end
end
