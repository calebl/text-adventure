# See lib/middleware/stale_schema_guard.rb. Sits immediately after Rails' own
# pending-migration check, which covers the migration that has not been run
# yet; this covers the one that was run after this process started.
if Rails.env.development?
  require Rails.root.join("lib/middleware/stale_schema_guard")

  Rails.application.config.app_middleware.insert_after(
    ActiveRecord::Migration::CheckPending, StaleSchemaGuard
  )
end
