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
    model = create(:model, :ollama)
    chat = create(:chat, playthrough: @playthrough, model: model)
    answer = create(:message, :assistant, chat: chat, model: nil, input_tokens: nil, output_tokens: nil)
    create(:tool_call, message: answer)
    RubyLLM::ActiveRecord::Usage.create!(
      chat: chat, message: answer, operation: "chat", provider: model.provider,
      model: model.model_id, status: "succeeded", input_tokens: 120, output_tokens: 40
    )
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
      chat_ids = connection.select_values("SELECT id FROM chats WHERE playthrough_id = #{@playthrough.id}")
      if chat_ids.any?
        list = chat_ids.join(",")
        message_ids = connection.select_values("SELECT id FROM messages WHERE chat_id IN (#{list})")
        connection.execute("DELETE FROM ruby_llm_usages WHERE chat_type = 'Chat' AND chat_id IN (#{list})")
        if message_ids.any?
          message_list = message_ids.join(",")
          connection.execute("DELETE FROM ruby_llm_tool_calls WHERE message_type = 'Message' AND message_id IN (#{message_list})")
          connection.execute("DELETE FROM messages WHERE id IN (#{message_list})")
        end
      end
      connection.execute("DELETE FROM chats WHERE playthrough_id = #{@playthrough.id}")
      connection.execute("DELETE FROM playthroughs WHERE id = #{@playthrough.id}")
    end
    if story_ids.any?
      list = story_ids.join(",")
      # Each factory story brought its own universe, and a universe left behind
      # outlives this non-transactional test and fails whatever next counts them
      # on this worker (`Story::DeletionTest`'s "no orphans at all").
      universe_ids = connection.select_values("SELECT universe_id FROM stories WHERE id IN (#{list})").join(",")
      connection.execute("DELETE FROM items WHERE location_id IN (SELECT id FROM locations WHERE story_id IN (#{list}))")
      connection.execute("DELETE FROM characters_scenes WHERE scene_id IN (SELECT id FROM scenes WHERE story_id IN (#{list}))")
      connection.execute("DELETE FROM scenes WHERE story_id IN (#{list})")
      connection.execute("DELETE FROM location_connections WHERE location_id IN (SELECT id FROM locations WHERE story_id IN (#{list}))")
      connection.execute("DELETE FROM locations WHERE story_id IN (#{list})")
      connection.execute("DELETE FROM characters WHERE story_id IN (#{list})")
      connection.execute("DELETE FROM stories WHERE id IN (#{list})")
      if universe_ids.present?
        orphaned = "id IN (#{universe_ids}) AND id NOT IN (SELECT universe_id FROM stories)"
        connection.execute("DELETE FROM races WHERE universe_id IN (SELECT id FROM universes WHERE #{orphaned})")
        connection.execute("DELETE FROM universes WHERE #{orphaned}")
      end
    end
    connection.execute("PRAGMA foreign_keys = ON")
  end

  test "the package is a gzipped primary DB holding only this story and playthrough" do
    requested = @dir.join("package.sqlite3")
    archive = Playthrough::SqlitePackage.new(@playthrough).write!(requested)

    assert_equal Pathname("#{requested}.gz"), archive
    assert archive.exist?
    assert_not requested.exist?, "bare sqlite should be removed after gzip"
    assert Playthrough::SqlitePackage.metadata_path(archive).exist?

    meta = JSON.parse(Playthrough::SqlitePackage.metadata_path(archive).read)
    assert_equal "playthrough_sqlite_package", meta.fetch("kind")
    assert_equal "Package Fixture Story", meta.dig("playthrough", "story")
    assert meta.fetch("compressed")
    assert meta.dig("git", "sha").present?
    assert_equal `git rev-parse HEAD`.strip, meta.dig("git", "sha")
    assert_includes [ true, false ], meta.dig("git", "dirty")

    sqlite = Playthrough::SqlitePackage.expand!(archive)
    assert sqlite.exist?

    original = ActiveRecord::Base.connection_db_config
    begin
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: sqlite.to_s,
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
      assert_equal "gemma3:12b", RubyLLM::ActiveRecord::Model.sole.model_id
      assert_equal 1, RubyLLM::ActiveRecord::ToolCall.count
      usage = RubyLLM::ActiveRecord::Usage.sole
      assert_equal "gemma3:12b", usage.model
      assert_equal 120, usage.input_tokens
      assert_equal 40, usage.output_tokens
    ensure
      ActiveRecord::Base.establish_connection(original)
    end
  end
end
