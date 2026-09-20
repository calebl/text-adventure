# ONE PLAYTHROUGH AS A MINIATURE PRIMARY DATABASE, for debugging.
#
# WHY IT EXISTS. A GitHub issue about a played-in world needs the real rows --
# journals, chats, scenes, the story graph that playthrough hangs from -- in a
# form an agent can boot Rails against. `Playthrough::Exporter` is the readable
# JSON companion; this is the restoreable one. It is NOT a slice of
# `playthrough_*` tables alone: a playthrough is meaningless without its story,
# so the package is that story's world plus this playthrough's progress.
#
# MODE. The shipped artifact is a gzipped SQLite file (`*.sqlite3.gz`) under
# `tmp/playthrough-packages/`. Drag-and-drop it onto the GitHub issue -- do not
# commit it. Expand, then open with `DATABASE_URL=sqlite3:path bin/rails runner
# ...`. There is no import-into-an-existing-database path -- that would need ID
# remapping across journals and is a different tool.
#
# HOW. Rows are read from the current primary connection into memory, a fresh
# file is given `db/schema.rb`, the rows are written back with foreign keys
# deferred, and the file is gzipped for issue evidence. Lab tables stay empty.
# Queue and cable are not primary tables and are not here.
#
# READ ONLY against the source. Nothing here advances a clock or asks a model.
class Playthrough::SqlitePackage
  METADATA_SUFFIX = ".meta.json"
  DIRECTORY = Rails.root.join("tmp/playthrough-packages")

  # Tables that belong to this playthrough by `playthrough_id`.
  PLAYTHROUGH_TABLES = %w[
    playthrough_beats
    playthrough_blows
    playthrough_commands
    playthrough_drifts
    playthrough_endings
    playthrough_feedbacks
    playthrough_npc_states
    playthrough_overreaches
    playthrough_passages
    playthrough_tolls
    playthrough_vitals
    playthrough_volitions
  ].freeze

  attr_reader :playthrough, :warnings

  def initialize(playthrough)
    @playthrough = playthrough
    @warnings = []
  end

  def story = playthrough.story
  def universe = story.universe

  def self.default_path(playthrough)
    story_slug = WorldSeed.slug(playthrough.story.title)
    who = WorldSeed.slug(playthrough.character&.fullname.presence || "unstarted")
    DIRECTORY.join("#{story_slug}--#{who}.sqlite3.gz")
  end

  def self.metadata_path(path) = Pathname.new("#{path}#{METADATA_SUFFIX}")

  # Path to the uncompressed sqlite beside an archive, or the archive itself
  # when it is already a bare `.sqlite3`.
  def self.sqlite_path(path)
    path = Pathname.new(path)
    path.to_s.end_with?(".gz") ? Pathname.new(path.to_s.delete_suffix(".gz")) : path
  end

  # Expand a `.sqlite3.gz` (or pass through a bare `.sqlite3`) and return the
  # sqlite path Rails can open. Overwrites the destination.
  def self.expand!(archive, destination: nil)
    archive = Pathname.new(archive)
    raise ArgumentError, "#{archive} does not exist" unless archive.exist?

    destination = Pathname.new(destination || sqlite_path(archive))
    destination.dirname.mkpath

    if archive.to_s.end_with?(".gz")
      require "zlib"
      destination.binwrite(Zlib.gunzip(archive.binread))
    else
      FileUtils.cp(archive, destination) unless archive == destination
    end
    destination
  end

  # Build the gzipped package at `path` and return the archive path. Accepts a
  # bare `.sqlite3` path and writes `*.sqlite3.gz` beside (and instead of) it.
  def write!(path = nil)
    requested = Pathname.new(path || self.class.default_path(playthrough))
    archive = requested.to_s.end_with?(".gz") ? requested : Pathname("#{requested}.gz")
    sqlite = self.class.sqlite_path(archive)

    archive.dirname.mkpath
    [ archive, sqlite, self.class.metadata_path(archive) ].each { |file| file.delete if file.exist? }

    bundle = extract_bundle
    materialize!(sqlite, bundle)
    compress!(sqlite, archive)
    sqlite.delete
    write_metadata!(archive, bundle)
    archive
  end

  private

  # ------------------------------------------------------------------------
  # extract from the live primary
  # ------------------------------------------------------------------------

  def extract_bundle
    connection = ActiveRecord::Base.connection
    scene_ids = playthrough.scene_chain.map(&:id)
    location_ids = story.locations.order(:id).pluck(:id)
    character_ids = story.characters.order(:id).pluck(:id)
    quest_ids = story.quests.order(:id).pluck(:id)
    chat_ids = playthrough.chats.order(:id).pluck(:id)
    message_ids = message_ids_for(connection, chat_ids)
    model_ids = model_ids_for(connection, message_ids)
    template_ids = Item.in_story(story).templates.order(:id).pluck(:id)
    playthrough_item_ids = playthrough.items.order(:id).pluck(:id)
    mechanic_ids = story.world_mechanics.order(:id).pluck(:id)
    event_ids = world_event_ids_for(connection, mechanic_ids)

    {
      "universes" => rows_by_id(connection, "universes", [ universe.id ]),
      "races" => rows_where(connection, "races", "universe_id", [ universe.id ]),
      "stories" => rows_by_id(connection, "stories", [ story.id ]),
      "locations" => ordered_locations(connection, location_ids),
      "characters" => rows_by_id(connection, "characters", character_ids),
      "items" => rows_by_id(connection, "items", template_ids + playthrough_item_ids),
      "location_connections" => location_connection_rows(connection, location_ids),
      "quests" => rows_by_id(connection, "quests", quest_ids),
      "quest_steps" => rows_where(connection, "quest_steps", "quest_id", quest_ids),
      "quest_outcomes" => rows_where(connection, "quest_outcomes", "quest_id", quest_ids),
      "world_mechanics" => rows_by_id(connection, "world_mechanics", mechanic_ids),
      "world_events" => rows_by_id(connection, "world_events", event_ids),
      "locations_world_events" => join_rows(connection, "locations_world_events",
                                            "world_event_id", event_ids, location_ids: location_ids),
      "scenes" => rows_by_id(connection, "scenes", scene_ids),
      "characters_scenes" => join_rows(connection, "characters_scenes", "scene_id", scene_ids),
      "interactions" => rows_where(connection, "interactions", "scene_id", scene_ids),
      "playthroughs" => rows_by_id(connection, "playthroughs", [ playthrough.id ]),
      "playthrough_tables" => PLAYTHROUGH_TABLES.to_h do |table|
        [ table, rows_where(connection, table, "playthrough_id", [ playthrough.id ]) ]
      end,
      "models" => rows_by_id(connection, "models", model_ids),
      "chats" => rows_by_id(connection, "chats", chat_ids),
      "messages" => rows_by_id(connection, "messages", message_ids),
      "tool_calls" => rows_where(connection, "tool_calls", "message_id", message_ids)
    }
  end

  def message_ids_for(connection, chat_ids)
    return [] if chat_ids.empty?

    connection.select_values(
      "SELECT id FROM messages WHERE chat_id IN (#{quoted_list(connection, chat_ids)}) ORDER BY id"
    )
  end

  def model_ids_for(connection, message_ids)
    return [] if message_ids.empty?

    connection.select_values(
      "SELECT DISTINCT model_id FROM messages WHERE id IN (#{quoted_list(connection, message_ids)}) " \
      "AND model_id IS NOT NULL ORDER BY model_id"
    )
  end

  def world_event_ids_for(connection, mechanic_ids)
    story_events = connection.select_values(
      "SELECT id FROM world_events WHERE story_id = #{connection.quote(story.id)} " \
      "AND (playthrough_id IS NULL OR playthrough_id = #{connection.quote(playthrough.id)}) ORDER BY id"
    )
    return story_events if mechanic_ids.empty?

    (story_events + connection.select_values(
      "SELECT id FROM world_events WHERE world_mechanic_id IN (#{quoted_list(connection, mechanic_ids)}) ORDER BY id"
    )).uniq
  end

  def ordered_locations(connection, location_ids)
    rows = rows_by_id(connection, "locations", location_ids)
    placed = []
    remaining = rows.dup
    # Parents before children so a reader skimming the file sees containment
    # order; foreign_keys are off on insert either way.
    while remaining.any?
      ready, remaining = remaining.partition do |row|
        parent = row["parent_location_id"]
        parent.nil? || placed.any? { |done| done["id"] == parent }
      end
      if ready.empty?
        @warnings << "location containment cycle or missing parent; writing remaining locations unordered"
        placed.concat(remaining)
        break
      end
      placed.concat(ready)
    end
    placed
  end

  def location_connection_rows(connection, location_ids)
    return [] if location_ids.empty?

    list = quoted_list(connection, location_ids)
    connection.exec_query(
      "SELECT * FROM location_connections WHERE location_id IN (#{list}) " \
      "AND connected_location_id IN (#{list}) ORDER BY id"
    ).to_a
  end

  def rows_by_id(connection, table, ids)
    ids = Array(ids).compact.uniq
    return [] if ids.empty?

    connection.exec_query(
      "SELECT * FROM #{table} WHERE id IN (#{quoted_list(connection, ids)}) ORDER BY id"
    ).to_a
  end

  def rows_where(connection, table, column, ids)
    ids = Array(ids).compact.uniq
    return [] if ids.empty?
    return [] unless connection.table_exists?(table)

    connection.exec_query(
      "SELECT * FROM #{table} WHERE #{column} IN (#{quoted_list(connection, ids)}) ORDER BY id"
    ).to_a
  end

  def join_rows(connection, table, column, ids, location_ids: nil)
    ids = Array(ids).compact.uniq
    return [] if ids.empty?
    return [] unless connection.table_exists?(table)

    sql = "SELECT * FROM #{table} WHERE #{column} IN (#{quoted_list(connection, ids)})"
    if location_ids
      location_ids = Array(location_ids).compact.uniq
      return [] if location_ids.empty?

      sql += " AND location_id IN (#{quoted_list(connection, location_ids)})"
    end
    connection.exec_query(sql).to_a
  end

  def quoted_list(connection, ids) = ids.map { |id| connection.quote(id) }.join(", ")

  # ------------------------------------------------------------------------
  # materialize into a fresh file
  # ------------------------------------------------------------------------

  def materialize!(path, bundle)
    original = ActiveRecord::Base.connection_db_config
    begin
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: path.to_s,
                                              timeout: 15_000, pool: 5)
      ActiveRecord::Schema.verbose = false
      load Rails.root.join("db/schema.rb")

      connection = ActiveRecord::Base.connection
      connection.execute("PRAGMA foreign_keys = OFF")
      insert_table(connection, "universes", bundle["universes"])
      insert_table(connection, "races", bundle["races"])
      insert_table(connection, "stories", bundle["stories"])
      insert_table(connection, "locations", bundle["locations"])
      insert_table(connection, "characters", bundle["characters"])
      insert_table(connection, "items", bundle["items"])
      insert_table(connection, "location_connections", bundle["location_connections"])
      insert_table(connection, "quests", bundle["quests"])
      insert_table(connection, "quest_steps", bundle["quest_steps"])
      insert_table(connection, "quest_outcomes", bundle["quest_outcomes"])
      insert_table(connection, "world_mechanics", bundle["world_mechanics"])
      insert_table(connection, "world_events", bundle["world_events"])
      insert_table(connection, "locations_world_events", bundle["locations_world_events"])
      insert_table(connection, "scenes", bundle["scenes"])
      insert_table(connection, "characters_scenes", bundle["characters_scenes"])
      insert_table(connection, "interactions", bundle["interactions"])
      insert_table(connection, "playthroughs", bundle["playthroughs"])
      bundle["playthrough_tables"].each do |table, rows|
        insert_table(connection, table, rows)
      end
      insert_table(connection, "models", bundle["models"])
      insert_table(connection, "chats", bundle["chats"])
      insert_table(connection, "messages", bundle["messages"])
      insert_table(connection, "tool_calls", bundle["tool_calls"])
      connection.execute("PRAGMA foreign_keys = ON")
      # Compact before gzip: freelist pages compress poorly and cost bytes on
      # the evidence file for nothing.
      connection.execute("VACUUM")
    ensure
      ActiveRecord::Base.establish_connection(original)
    end
  end

  def insert_table(connection, table, rows)
    return if rows.blank?
    raise "refusing to write unknown table #{table}" unless connection.table_exists?(table)

    columns = rows.first.keys
    cols_sql = columns.map { |column| connection.quote_column_name(column) }.join(", ")
    rows.each do |row|
      values = columns.map { |column| connection.quote(row[column]) }.join(", ")
      connection.execute("INSERT INTO #{table} (#{cols_sql}) VALUES (#{values})")
    end
  end

  def write_metadata!(path, bundle)
    meta = {
      "format" => 1,
      "kind" => "playthrough_sqlite_package",
      "dumped_at" => Time.current.utc.iso8601,
      "rails_env" => Rails.env,
      "playthrough" => {
        "id" => playthrough.id,
        "story" => story.title,
        "protagonist" => playthrough.character&.fullname,
        "current_location" => playthrough.current_location&.name
      },
      "counts" => {
        "locations" => bundle["locations"].size,
        "characters" => bundle["characters"].size,
        "scenes" => bundle["scenes"].size,
        "commands" => bundle["playthrough_tables"]["playthrough_commands"].size,
        "chats" => bundle["chats"].size,
        "messages" => bundle["messages"].size
      },
      "compressed" => true,
      "open_with" => [
        "gunzip -k #{path}",
        "DATABASE_URL=sqlite3:#{self.class.sqlite_path(path)} bin/rails runner " \
          "'p Playthrough.find(#{playthrough.id}).story.title'"
      ]
    }
    self.class.metadata_path(path).write(JSON.pretty_generate(meta))
  end

  def compress!(sqlite, archive)
    require "zlib"

    archive.binwrite(Zlib.gzip(sqlite.binread, level: Zlib::BEST_COMPRESSION))
  end
end
