# Serializes work which spans model calls without holding SQLite's one writer.
# The lock files live beside the primary database so every web/worker process
# using that database also uses the same locks, including across deploys.
#
# flock is an OS claim, not a lease: a slow provider cannot expire it, and the
# kernel releases it when a worker dies. Never unlink these files -- a waiter
# may still hold the old inode. This deliberately follows the app's local
# SQLite deployment; distributing the database to separate hosts would require
# replacing this primitive along with SQLite.
module GameLock
  class ReentrantError < StandardError; end

  def self.synchronize(scope, id)
    database = File.expand_path(ApplicationRecord.connection_db_config.database, Rails.root)
    directory = Pathname.new(database).dirname.join("game-locks")
    FileUtils.mkdir_p(directory)
    path = directory.join("#{File.basename(database)}-#{scope}-#{Integer(id)}.lock").to_s
    held = Thread.current[:game_locks] ||= {}
    raise ReentrantError, "The same game operation cannot run inside itself" if held[path]

    File.open(path, File::RDWR | File::CREAT, 0o600) do |file|
      file.flock(File::LOCK_EX)
      held[path] = true
      begin
        yield
      ensure
        held.delete(path)
        file.flock(File::LOCK_UN)
      end
    end
  end
end
