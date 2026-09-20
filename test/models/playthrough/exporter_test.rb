require "test_helper"

class Playthrough::ExporterTest < ActiveSupport::TestCase
  setup do
    @story = create(:story, title: "Cold Deck Running", genre: "sci-fi thriller")
    @opening = create(:location, story: @story, name: "Cargo Deck crawlspace")
    @shaft = create(:location, story: @story, name: "Gravity Core Maintenance Shaft")
    create(:location_connection, location: @opening, connected_location: @shaft,
                                 distance: "adjacent", travel_method: "climbing")
    create(:location_connection, location: @shaft, connected_location: @opening,
                                 distance: "adjacent", travel_method: "climbing")

    @chamber = create(:location, :with_a_footprint, story: @story, name: "Core Access Chamber",
                                                   width: 5, depth: 3)
    @room = create(:location, story: @story, name: "Core Access Chamber room 1",
                              parent_location: @chamber, x: 0, y: 0, z: 0, width: 5, depth: 3,
                              teaser: "A room inside Core Access Chamber, 5 by 3 paces on storey 0.")
    create(:location_connection, location: @shaft, connected_location: @room,
                                 distance: "adjacent", travel_method: "climbing")
    create(:location_connection, location: @room, connected_location: @shaft,
                                 distance: "adjacent", travel_method: "climbing")

    @hero = create(:character, story: @story, fullname: "Kael Veyra", is_protagonist: true,
                               location: @opening)
    @npc = create(:character, story: @story, fullname: "Mira Solis", location: @opening)

    opening_scene = create(:scene, :opening, story: @story, location: @opening,
                                             description: "The cold hits first.")
    @playthrough = create(:playthrough, story: @story, character: @hero,
                                        current_location: @opening, current_scene: opening_scene)

    create(:playthrough_npc_state, playthrough: @playthrough, character: @npc, location: @shaft)

    arrival = create(:scene, story: @story, location: @room, previous_scene: opening_scene,
                             resolved_action: "move", resolved_by: "grammar",
                             typed: "go Core Access Chamber",
                             description: "Heat instead of cold.",
                             story_timestamp: @story.start_time + 10.minutes,
                             acted_on: @chamber)
    @playthrough.update!(current_location: @room, current_scene: arrival)

    create(:playthrough_command, playthrough: @playthrough, command: "/go Core Access Chamber",
                                 status: "completed", result_scene: arrival,
                                 journal: {
                                   "version" => 1,
                                   "steps" => {
                                     "origin" => { "record" => "Location", "id" => @shaft.id },
                                     "outcome" => { "record" => "Scene", "id" => arrival.id,
                                                    "tolls" => [], "safety" => nil, "setup" => false }
                                   }
                                 })

    create(:playthrough_drift, playthrough: @playthrough, scene: arrival, location: @room,
                               action: "attack", command: "attack the core", offered: "",
                               story_timestamp: arrival.story_timestamp)

    create(:item, :lying, name: "a loose access panel", location: @room, playthrough: nil)
    create(:item, :carried, name: "a loose access panel", playthrough: @playthrough,
                  location: nil, character: nil)
  end

  test "reading the document writes nothing" do
    before = database_snapshot

    BaseAgent.stub(:new, -> { flunk "the exporter asked a model something" }) do
      Playthrough::Exporter.new(@playthrough).document
    end

    assert_equal before, database_snapshot
  end

  test "the document is keyed by names rather than database ids" do
    document = Playthrough::Exporter.new(@playthrough).document
    json = JSON.generate(document)

    assert_equal 1, document.fetch("format")
    assert_equal "Cold Deck Running", document.dig("story", "title")
    assert_equal "Kael Veyra", document.dig("playthrough", "protagonist")
    assert_equal "Core Access Chamber room 1", document.dig("playthrough", "current_location")
    assert_equal "Core Access Chamber", document.dig("playthrough", "containing_place")

    names = document.fetch("locations").map { |row| row.fetch("name") }
    assert_includes names, "Core Access Chamber room 1"
    room = document.fetch("locations").find { |row| row["name"] == "Core Access Chamber room 1" }
    assert_equal "Core Access Chamber", room.fetch("parent")
    assert room.fetch("placeholder_name")

    chamber = document.fetch("locations").find { |row| row["name"] == "Core Access Chamber" }
    assert chamber.fetch("place")
    assert chamber.fetch("laid_out")

    mira = document.fetch("characters").find { |row| row["fullname"] == "Mira Solis" }
    assert_equal "Cargo Deck crawlspace", mira.fetch("world_location")
    assert_equal "Gravity Core Maintenance Shaft", mira.dig("in_this_game", "location")

    assert(document.fetch("connections").any? { |edge| edge["between"].sort ==
      [ "Core Access Chamber room 1", "Gravity Core Maintenance Shaft" ].sort })

    turns = document.fetch("turns")
    assert_equal 2, turns.size
    assert_equal "arrival", turns.last.fetch("branch")
    assert_equal "go Core Access Chamber", turns.last.fetch("typed")
    assert_equal "Core Access Chamber", turns.last.fetch("acted_on")
    assert_equal "Core Access Chamber", turns.last.fetch("containing_place")

    command = document.fetch("commands").sole
    assert_equal "/go Core Access Chamber", command.fetch("command")
    assert_equal turns.last.fetch("key"), command.fetch("result_turn")
    origin = command.dig("journal", "steps", "origin")
    assert_equal "Location", origin.fetch("record")
    assert_equal "Gravity Core Maintenance Shaft", origin.fetch("name")
    assert_not origin.key?("id"), "journal locations must not carry database ids"

    drift = document.fetch("drifts").sole
    assert_equal "attack the core", drift.fetch("command")
    assert_equal turns.last.fetch("key"), drift.fetch("turn")

    refute_match(/"id"\s*:\s*\d+/, json, "the export must not leak integer database ids")
  end

  test "write! dumps pretty JSON under tmp/playthrough-exports by default" do
    path = Playthrough::Exporter.new(@playthrough).write!

    assert_equal Playthrough::Exporter::DIRECTORY, path.dirname
    assert_match(/cold-deck-running--kael-veyra\.json\z/, path.basename.to_s)
    parsed = JSON.parse(path.read)
    assert_equal "Cold Deck Running", parsed.dig("story", "title")
  ensure
    path&.delete if path&.exist?
  end

  # Row counts and the newest `updated_at` per table: same shape
  # `Playthrough::DebugTest` uses, so a write in place is caught too.
  def database_snapshot
    ActiveRecord::Base.connection.tables.sort.to_h do |table|
      rows = ActiveRecord::Base.connection.select_all("SELECT COUNT(*) AS c FROM #{table}").first["c"]
      updated =
        if ActiveRecord::Base.connection.column_exists?(table, :updated_at)
          ActiveRecord::Base.connection.select_all("SELECT MAX(updated_at) AS m FROM #{table}").first["m"]
        end

      [ table, [ rows, updated ] ]
    end
  end
end
