require "test_helper"
require "sqlite3"

class DatabaseDumpTest < ActiveSupport::TestCase
  # Dumps read what is on disk. A transactional example never commits the rows
  # it creates, so the Backup API would snapshot an empty world -- turn the
  # wrapper off for this file and clean up by hand.
  self.use_transactional_tests = false

  setup do
    @dir = Rails.root.join("tmp/database-dump-test-#{SecureRandom.hex(4)}")
    @dir.mkpath
    @playthrough = create(:playthrough, :in_scene)
    @playthrough.story.update!(title: "Dump Fixture Story")
  end

  teardown do
    story = @playthrough&.story
    @playthrough&.destroy
    story&.destroy
    FileUtils.rm_rf(@dir)
  end

  test "dump! writes a SQLite file that still holds the playthrough" do
    path = @dir.join("fixture.sqlite3")

    DatabaseDump.new.dump!(path, playthrough: @playthrough)

    assert path.exist?
    assert_equal "SQLite format 3\0", path.open("rb", &:read)[0, 16]

    meta = JSON.parse(DatabaseDump.metadata_path(path).read)
    assert_equal "primary_sqlite_dump", meta.fetch("kind")
    assert_equal @playthrough.id, meta.dig("playthrough", "id")
    assert_equal "Dump Fixture Story", meta.dig("playthrough", "story")

    rows = SQLite3::Database.open(path.to_s) do |db|
      db.execute("SELECT id FROM playthroughs WHERE id = ?", [ @playthrough.id ])
    end
    assert_equal [ [ @playthrough.id ] ], rows
  end

  test "restore! refuses to overwrite without force" do
    dump = @dir.join("fixture.sqlite3")
    destination = @dir.join("primary.sqlite3")
    DatabaseDump.new.dump!(dump)
    FileUtils.cp(dump, destination)

    error = assert_raises(ArgumentError) { DatabaseDump.new.restore!(dump, destination: destination) }
    assert_match(/FORCE|force/, error.message)
    assert destination.exist?
  end

  test "restore! replaces the destination and keeps a before-restore copy" do
    dump = @dir.join("fixture.sqlite3")
    destination = @dir.join("primary.sqlite3")
    DatabaseDump.new.dump!(dump, playthrough: @playthrough)
    File.write(destination, "not-the-dump")

    DatabaseDump.new.restore!(dump, force: true, destination: destination)

    assert_equal "SQLite format 3\0", destination.open("rb", &:read)[0, 16]
    assert Pathname.new("#{destination}.before-restore").exist?
    assert_equal "not-the-dump", Pathname.new("#{destination}.before-restore").read

    rows = SQLite3::Database.open(destination.to_s) do |db|
      db.execute("SELECT COUNT(*) FROM playthroughs WHERE id = ?", [ @playthrough.id ])
    end
    assert_equal [ [ 1 ] ], rows
  end

  test "restore! refuses a JSON export" do
    json = @dir.join("not-a-db.json")
    json.write("{}")

    error = assert_raises(ArgumentError) { DatabaseDump.new.restore!(json, force: true, destination: @dir.join("x.sqlite3")) }
    assert_match(/not a SQLite database/, error.message)
  end
end
