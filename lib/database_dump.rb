# A RESTOREABLE SNAPSHOT OF THE PRIMARY SQLITE DATABASE.
#
# WHY IT EXISTS. A name-keyed JSON export (`Playthrough::Exporter`) is for
# reading in an issue. Replaying the same rows in a running app needs the
# actual SQLite file: schema, foreign keys, chats, journals, everything the
# JSON deliberately flattened away. This is that file, taken consistently and
# put back the same way.
#
# HOW. After a WAL checkpoint, the primary file is copied with SQLite's Backup
# API (`SQLite3::Backup`) so an open ActiveRecord connection does not block
# the snapshot. `VACUUM INTO` is preferred when the connection is free -- it
# writes a compact file in one step -- and the Backup API is the fallback the
# test suite needs when the pool still holds a lock.
#
# SCOPE. The PRIMARY database only. Queue and cable are process infrastructure
# and are not part of a playthrough's world. A dump taken while playthrough N
# exists restores to a database that still has playthrough N -- and every other
# story that was in development at the time. That is deliberate: carving one
# playthrough's rows into a fresh file is a different tool and a fragile one.
#
# SAFETY. `#restore!` refuses to overwrite an existing primary database unless
# `force:` is true, and it refuses a path that is not a SQLite database. It
# does not stop Puma or Solid Queue; quit those first or risk a writer opening
# the old inode.
class DatabaseDump
  METADATA_SUFFIX = ".meta.json"
  DIRECTORY = Rails.root.join("tmp/database-dumps")

  # Compact online copy of the connected primary database to `path`. When a
  # playthrough is given, a sibling `.meta.json` records which game the dump
  # was taken for -- the file itself is still the whole primary database.
  def dump!(path, playthrough: nil)
    path = Pathname.new(path)
    path.dirname.mkpath
    path.delete if path.exist?

    connection = ActiveRecord::Base.connection
    unless connection.adapter_name.match?(/sqlite/i)
      raise "DatabaseDump only supports sqlite3, got #{connection.adapter_name}"
    end

    checkpoint_wal(connection)
    copy_primary_to!(path)

    write_metadata!(path, playthrough) if playthrough
    path
  end

  # Replace the primary database file with the dump at `path`. The previous
  # file is left beside it as `*.before-restore` unless `keep_previous:` is
  # false. `destination:` is for tests; production callers leave it nil.
  def restore!(path, force: false, keep_previous: true, destination: nil)
    path = Pathname.new(path)
    raise ArgumentError, "#{path} does not exist" unless path.exist?
    raise ArgumentError, "#{path} is not a SQLite database" unless sqlite_database?(path)

    destination = Pathname.new(destination || primary_database_path).expand_path
    if destination.exist? && !force
      raise ArgumentError,
            "#{destination} already exists; pass force: true (or FORCE=1) to replace it. " \
            "Quit Puma and bin/jobs first."
    end

    ActiveRecord::Base.connection_pool.with_connection do |connection|
      checkpoint_wal(connection) if connection.adapter_name.match?(/sqlite/i)
    end
    ActiveRecord::Base.connection_handler.clear_all_connections!(:all)

    destination.dirname.mkpath
    if destination.exist? && keep_previous
      backup = Pathname.new("#{destination}.before-restore")
      backup.delete if backup.exist?
      FileUtils.cp(destination, backup)
    end

    %w[-wal -shm].each do |suffix|
      sidecar = Pathname.new("#{destination}#{suffix}")
      sidecar.delete if sidecar.exist?
    end

    FileUtils.cp(path, destination)
    destination
  end

  def self.metadata_path(dump_path) = Pathname.new("#{dump_path}#{METADATA_SUFFIX}")

  def self.default_path(playthrough)
    story = WorldSeed.slug(playthrough.story.title)
    who = WorldSeed.slug(playthrough.character&.fullname.presence || "unstarted")
    DIRECTORY.join("#{story}--#{who}.sqlite3")
  end

  def primary_database_path
    config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "primary")
    config ||= ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).first
    raise "no primary database configured for #{Rails.env}" if config.nil?

    Pathname.new(config.database).expand_path(Rails.root)
  end

  private

  def checkpoint_wal(connection)
    connection.execute("PRAGMA wal_checkpoint(FULL)")
  rescue ActiveRecord::StatementInvalid => error
    raise unless locked_database?(error)
  end

  def copy_primary_to!(path)
    connection = ActiveRecord::Base.connection
    absolute = path.expand_path.to_s

    begin
      connection.execute("VACUUM INTO #{connection.quote(absolute)}")
      return
    rescue ActiveRecord::StatementInvalid => error
      raise unless vacuum_unavailable?(error)
    end

    backup_copy!(primary_database_path.to_s, absolute)
  end

  def backup_copy!(source, destination)
    require "sqlite3"

    src = SQLite3::Database.open(source)
    dst = SQLite3::Database.new(destination)
    backup = SQLite3::Backup.new(dst, "main", src, "main")
    begin
      loop do
        backup.step(-1)
        break if backup.remaining.zero?
      end
    ensure
      backup.finish
      dst.close
      src.close
    end
  end

  def locked_database?(error)
    return true if error.message.match?(/locked/i)

    cause = error.cause
    defined?(SQLite3::LockedException) && cause.is_a?(SQLite3::LockedException)
  end

  # VACUUM INTO needs a quiet connection: no open transaction (the test suite
  # wraps every example in one) and no lock held by a sibling. Both fall through
  # to the Backup API, which tolerates them.
  def vacuum_unavailable?(error)
    locked_database?(error) || error.message.match?(/VACUUM|transaction/i)
  end

  def sqlite_database?(path)
    path.open("rb") { |io| io.read(16) } == "SQLite format 3\0"
  rescue Errno::ENOENT
    false
  end

  def write_metadata!(path, playthrough)
    meta = {
      "format" => 1,
      "kind" => "primary_sqlite_dump",
      "dumped_at" => Time.current.utc.iso8601,
      "rails_env" => Rails.env,
      "source" => primary_database_path.relative_path_from(Rails.root).to_s,
      "playthrough" => {
        "id" => playthrough.id,
        "story" => playthrough.story.title,
        "protagonist" => playthrough.character&.fullname,
        "current_location" => playthrough.current_location&.name
      }
    }
    self.class.metadata_path(path).write(JSON.pretty_generate(meta))
  end
end
