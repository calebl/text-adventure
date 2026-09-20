require "test_helper"

class Playthrough::SqlitePackageTest < ActiveSupport::TestCase
  # Packaging reads committed rows off disk into a second database. A
  # transactional example never commits, so the package would miss its own
  # fixture -- turn the wrapper off and clean up by hand.
  self.use_transactional_tests = false

  setup do
    @dir = Rails.root.join("tmp/sqlite-package-test-#{SecureRandom.hex(4)}")
    @dir.mkpath
    @story = create(:story, title: "Package Fixture Story", genre: "test")
    @opening = create(:location, story: @story, name: "The Foyer")
    @hall = create(:location, story: @story, name: "The Hall")
    create(:location_connection, location: @opening, connected_location: @hall,
                                 distance: "adjacent", travel_method: "walking")
    create(:location_connection, location: @hall, connected_location: @opening,
                                 distance: "adjacent", travel_method: "walking")
    @hero = create(:character, story: @story, fullname: "Ada Package", is_protagonist: true,
                               location: @opening)
    other_story = create(:story, title: "Other World Not Packaged")
    create(:location, story: other_story, name: "Should Not Appear")

    opening_scene = create(:scene, :opening, story: @story, location: @opening,
                                             description: "You stand in the foyer.")
    @playthrough = create(:playthrough, story: @story, character: @hero,
                                        current_location: @opening, current_scene: opening_scene)
    create(:playthrough_command, playthrough: @playthrough, command: "/look",
                                 status: "completed", result_scene: opening_scene)
    create(:item, :lying, name: "brass key", location: @opening, playthrough: nil)
    create(:item, :carried, name: "brass key", playthrough: @playthrough, location: nil, character: nil)
  end

  teardown do
    FileUtils.rm_rf(@dir)
    connection = ActiveRecord::Base.connection
    connection.execute("PRAGMA foreign_keys = OFF")
    story_ids = [ @story&.id, Story.find_by(title: "Other World Not Packaged")&.id ].compact
    if @playthrough
      PLAYTHROUGH_TABLES = Playthrough::SqlitePackage::PLAYTHROUGH_TABLES
      PLAYTHROUGH_TABLES.each do |table|
        connection.execute("DELETE FROM #{table} WHERE playthrough_id = #{@playthrough.id}")
      end
      connection.execute("DELETE FROM items WHERE playthrough_id = #{@playthrough.id}")
      connection.execute("DELETE FROM chats WHERE playthrough_id = #{@playthrough.id}")
      connection.execute("DELETE FROM playthroughs WHERE id = #{@playthrough.id}")
    end
    if story_ids.any?
      list = story_ids.join(",")
      connection.execute("DELETE FROM items WHERE location_id IN (SELECT id FROM locations WHERE story_id IN (#{list}))")
      connection.execute("DELETE FROM characters_scenes WHERE scene_id IN (SELECT id FROM scenes WHERE story_id IN (#{list}))")
      connection.execute("DELETE FROM scenes WHERE story_id IN (#{list})")
      connection.execute("DELETE FROM location_connections WHERE location_id IN (SELECT id FROM locations WHERE story_id IN (#{list}))")
      connection.execute("DELETE FROM locations WHERE story_id IN (#{list})")
      connection.execute("DELETE FROM characters WHERE story_id IN (#{list})")
      connection.execute("DELETE FROM stories WHERE id IN (#{list})")
    end
    connection.execute("PRAGMA foreign_keys = ON")
  end

  test "the package is a primary DB holding only this story and playthrough" do
    path = @dir.join("package.sqlite3")
    Playthrough::SqlitePackage.new(@playthrough).write!(path)

    assert path.exist?
    assert Playthrough::SqlitePackage.metadata_path(path).exist?

    meta = JSON.parse(Playthrough::SqlitePackage.metadata_path(path).read)
    assert_equal "playthrough_sqlite_package", meta.fetch("kind")
    assert_equal "Package Fixture Story", meta.dig("playthrough", "story")

    original = ActiveRecord::Base.connection_db_config
    begin
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: path.to_s,
                                              timeout: 5_000, pool: 5)

      assert_equal 1, Story.count
      assert_equal "Package Fixture Story", Story.sole.title
      assert_equal 1, Playthrough.count
      assert_equal @playthrough.id, Playthrough.sole.id
      assert_equal [ "The Foyer", "The Hall" ].sort, Location.order(:name).pluck(:name)
      assert_nil Location.find_by(name: "Should Not Appear")
      assert_equal 1, Item.where(playthrough_id: nil).count
      assert_equal 1, Item.where(playthrough_id: @playthrough.id).count
      assert_equal "/look", Playthrough::Command.sole.command
    ensure
      ActiveRecord::Base.establish_connection(original)
    end
  end
end
