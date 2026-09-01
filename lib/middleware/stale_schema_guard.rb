# Says "restart the server" when the database has been migrated out from under
# a running one, instead of letting the first attribute the code reaches for
# fail eighty seconds into a turn.
#
# THE FAILURE THIS EXISTS FOR, because it is not obvious and it cost a real
# turn: a development server boots, and ActiveRecord caches each table's columns
# the first time a model touches it. A migration then runs -- in another
# terminal, which is the only way migrations are ever run -- and that process
# never sees it. It keeps a `Scene` class defined from the columns that existed
# at boot, so `scene.is_opening?` raises NoMethodError for a column that is
# right there in the database. Nothing is wrong with the data and nothing is
# wrong with the code; the process is simply old.
#
# Rails already guards the other half of this. `ActiveRecord::Migration::CheckPending`
# (config.active_record.migration_error = :page_load) refuses a request while a
# migration FILE is unapplied, and it re-checks whenever the migration directory
# changes -- so it catches the gap between pulling a migration and running it,
# and it stops catching the moment the migration runs. This covers what happens
# next: the schema moved, and the process that was already running still has
# yesterday's idea of it.
#
# IT REPORTS RATHER THAN REPAIRS, deliberately. Recovering in place is not one
# call: resetting column information leaves the connection's prepared statements
# still selecting the old columns, so the honest fix is a new process, and
# dropping the pool mid-request to fake one is machinery this does not need. A
# developer who is told to restart restarts in two seconds.
#
# Development only -- production servers are restarted by their deploy.
class StaleSchemaGuard
  class StaleSchemaError < StandardError; end

  # `version` is injectable so the test can move the schema without migrating
  # anything.
  def initialize(app, version: nil)
    @app = app
    @version = version
    @mutex = Mutex.new
  end

  def call(env)
    check!
    @app.call(env)
  end

  private

  # The baseline is the FIRST request rather than boot, and that is the right
  # moment: nothing has cached a column list until something has read a record,
  # and reading the version at boot would open a database connection during
  # initialization for no other reason.
  def check!
    version = current_version
    return if version.nil?

    stale = @mutex.synchronize do
      @booted ||= version
      version != @booted
    end

    return unless stale

    raise StaleSchemaError, <<~MESSAGE
      The database was migrated while this server was running.

      It booted against schema version #{@booted} and the database is now at #{version}.
      Anything this process has already loaded still has the columns from before the
      migration, which surfaces as `undefined method` for a column that exists.

      Restart the server (Ctrl-C, then `bin/rails server`).
    MESSAGE
  end

  def current_version
    return @version.call if @version

    ActiveRecord::Base.connection_pool.migration_context.current_version
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
    # No database yet, or no schema_migrations table. `db:prepare` is the
    # answer to that and Rails says so already; this has nothing to add.
    nil
  end
end
