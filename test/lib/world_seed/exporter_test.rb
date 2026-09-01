require "test_helper"

class WorldSeed::ExporterTest < ActiveSupport::TestCase
  def setup
    @universe = create(:universe, race_names: [ "Elf", "Dwarf" ])
    @story = create(:story, universe: @universe, title: "A World To Export")
    @opening = create(:location, story: @story, name: "The Opening Room")
    @stub = create(:location, :stub, story: @story, name: "Somewhere Else")
    connect(@opening, @stub)
    connect(@stub, @opening)
    # The one Scene that is world rather than progress, and the one the loader
    # now requires. See the class comment on WorldSeed::Exporter.
    @arrival = create(:scene, :opening, story: @story, location: @opening,
                                        description: "The door is still swinging behind you.",
                                        summary: "The story opens.")
  end

  test "exports the whole graph" do
    document = WorldSeed::Exporter.new(@story).document

    assert_equal WorldSeed::FORMAT, document["format"]
    assert_equal @universe.physics, document.dig("universe", "physics")
    assert_equal %w[Dwarf Elf], document.dig("universe", "races").map { |race| race["name"] }
    assert_equal "A World To Export", document.dig("story", "title")
    assert_equal @story.genre, document.dig("story", "genre")
    assert_equal @story.preface, document.dig("story", "preface")
    assert_equal [ "The Opening Room", "Somewhere Else" ], document["locations"].map { |l| l["name"] }
    assert_equal %w[realized stub], document["locations"].map { |l| l["detail_level"] }
  end

  test "marks the opening location, which the loader has to create first" do
    document = WorldSeed::Exporter.new(@story).document

    assert_equal [ true ], document["locations"].filter_map { |location| location["opening"] }
    assert_equal @story.opening_location.name, document["locations"].first["name"]
  end

  test "writes an undirected edge once, and no time_to_travel" do
    document = WorldSeed::Exporter.new(@story).document

    assert_equal 1, document["connections"].size
    edge = document["connections"].first
    assert_equal [ "The Opening Room", "Somewhere Else" ], edge["between"]
    assert_equal "adjacent", edge["distance"]
    assert_equal "walking", edge["travel_method"]
    assert_not edge.key?("time_to_travel"), "time_to_travel is derived, not stored in the seed"
  end

  test "exports a character with its race by name and its items" do
    character = create(:character, story: @story, fullname: "Someone Specific", is_protagonist: true)
    create(:item, character: character, name: "A Sealed Letter")

    document = WorldSeed::Exporter.new(@story).document.fetch("characters").first

    assert_equal "Someone Specific", document["fullname"]
    assert_equal character.race.name, document["race"]
    assert_equal true, document["is_protagonist"]
    assert_equal [ "A Sealed Letter" ], document["items"].map { |item| item["name"] }
  end

  test "warns about a one-way edge instead of dropping it" do
    LocationConnection.find_by(location: @stub, connected_location: @opening).destroy!

    exporter = WorldSeed::Exporter.new(@story)
    exporter.document

    assert_equal 1, exporter.document["connections"].size
    assert_includes exporter.warnings.join("\n"), "only one direction exists"
  end

  test "warns about a value the fixed tables no longer accept" do
    LocationConnection.where(location: @opening).update_all(distance: "Just below the window")

    exporter = WorldSeed::Exporter.new(@story)
    exporter.document

    assert_includes exporter.warnings.join("\n"), "LocationConnection::DISTANCES"
  end

  # The opening arrival is world; every other scene is somebody's way through it.
  test "exports the opening arrival by natural key, and no timestamp" do
    cast = create(:character, story: @story, fullname: "Someone Present")
    @arrival.characters << cast

    document = WorldSeed::Exporter.new(@story).document.fetch("opening_scene")

    assert_equal "The Opening Room", document["location"]
    assert_equal [ "Someone Present" ], document["characters"]
    assert_equal "The door is still swinging behind you.", document["description"]
    assert_equal "The story opens.", document["summary"]
    assert_not document.key?("story_timestamp"), "an opening arrival happens at the story's start_time"
  end

  # A story built before opening arrivals existed exports without one, and the
  # loader refuses such a file -- so the exporter has to say so rather than
  # producing a file that fails three records into a seed.
  # --- a world's own mechanics ---------------------------------------------

  test "exports a world's mechanics, and never a last_run_at" do
    create(:world_mechanic, story: @story, name: "The nightly rearrangement",
                            description: "Nocturna floods the city at midnight.",
                            last_run_at: @story.start_time + 1.day)

    mechanics = WorldSeed::Exporter.new(@story).document["mechanics"]

    assert_equal 1, mechanics.size
    assert_equal "The nightly rearrangement", mechanics.first["name"]
    assert_equal "shuffle_connections", mechanics.first["kind"]
    assert_equal "nightly", mechanics.first["cadence"]
    assert_equal "Nocturna floods the city at midnight.", mechanics.first["description"]
    assert_not mechanics.first.key?("last_run_at"), "how far a mechanic has got is progress, not world"
  end

  test "a story with no mechanics has no mechanics key at all" do
    assert_not WorldSeed::Exporter.new(@story).document.key?("mechanics")
  end

  test "exports which locations move, and stays quiet about the ones that do not" do
    @stub.update!(mobile: true)

    locations = WorldSeed::Exporter.new(@story).document["locations"]

    assert_not locations.first.key?("mobile"), "a place that stays put should not say so"
    assert_equal true, locations.last["mobile"]
  end

  test "warns about the world events it does not export" do
    mechanic = create(:world_mechanic, story: @story)
    create(:world_event, world_mechanic: mechanic, story: @story)

    exporter = WorldSeed::Exporter.new(@story)
    exporter.document

    assert exporter.warnings.any? { |warning| warning.include?("world event") }
  end

  test "warns loudly when a story has no opening arrival to export" do
    @arrival.destroy!

    exporter = WorldSeed::Exporter.new(@story)

    assert_nil exporter.document["opening_scene"]
    assert_includes exporter.warnings.join("\n"), "WILL NOT LOAD"
  end

  test "warns about the progress it does not export" do
    create(:scene, story: @story, location: @opening)
    create(:playthrough, story: @story)

    exporter = WorldSeed::Exporter.new(@story)
    exporter.document

    assert_includes exporter.warnings.join("\n"), "scene(s) not exported"
    assert_includes exporter.warnings.join("\n"), "playthrough(s) not exported"
  end

  # CONVERSATION HISTORY IS PROGRESS, and it is left out deliberately rather
  # than by omission -- so it is said out loud like everything else that is. A
  # `Chat` is what one player said to one character on one playthrough; seeding
  # it would hand a character memories of somebody who does not exist.
  test "warns about the conversation history it does not export" do
    playthrough = create(:playthrough, story: @story)
    create(:chat, playthrough: playthrough, purpose: Chat::CHARACTER)

    exporter = WorldSeed::Exporter.new(@story)
    document = exporter.document

    assert_includes exporter.warnings.join("\n"), "conversation(s) not exported"
    assert_equal [], document.keys & %w[chats messages conversations]
  end

  test "writes a commented, parseable file" do
    Dir.mktmpdir do |directory|
      path = WorldSeed::Exporter.new(@story).write!(path: File.join(directory, "exported.yml"))
      contents = path.read

      assert contents.start_with?("# A World To Export"), "the file opens with a comment naming the world"
      assert_match(/hand/i, contents)
      assert_equal "A World To Export", WorldSeed.parse(contents).dig("story", "title")
    end
  end

  test "keeps a hand-written comment header when re-exporting over a file" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "exported.yml")
      File.write(path, "# A note somebody wrote by hand.\n#\n# Second line.\n")

      contents = WorldSeed::Exporter.new(@story).write!(path: path).read

      assert contents.start_with?("# A note somebody wrote by hand.\n#\n# Second line.\n")
      assert_equal "A World To Export", WorldSeed.parse(contents).dig("story", "title")
    end
  end

  test "names its own file after the story title" do
    assert_equal "a-world-to-export", WorldSeed.slug(@story.title)
    assert_equal "the-lunar-cartographer", WorldSeed.slug("The Lunar Cartographer")
  end

  test "keeps prose in a block scalar so an edit is a one-line diff" do
    yaml = WorldSeed.dump(WorldSeed::Exporter.new(@story).document)

    assert_includes yaml, "  physics: |-\n"
    assert_equal @universe.physics, WorldSeed.parse(yaml).dig("universe", "physics")
  end

  # The point of the exporter is that a world survives a schema change: export,
  # reload, export, and the file has to be the same file. If it is not, the
  # checked-in worlds drift from what the tooling produces.
  test "a world round-trips through export, load and export unchanged" do
    first = WorldSeed.dump(WorldSeed::Exporter.new(@story).document)

    @story.destroy!
    @universe.destroy!
    reloaded = WorldSeed::Loader.new(WorldSeed.parse(first)).load!

    assert_equal first, WorldSeed.dump(WorldSeed::Exporter.new(reloaded).document)
  end

  # The same guarantee for the keys a moving world adds: `mobile` and
  # `mechanics` have to survive the same export -> load -> export loop, or the
  # checked-in world stops moving the next time somebody re-exports it.
  test "a moving world round-trips with its mechanics and its mobile places" do
    third = create(:location, :stub, story: @story, name: "The Fixed Tower")
    fourth = create(:location, :stub, story: @story, name: "The Fixed Circle")
    connect(@stub, third)
    connect(third, @stub)
    connect(@opening, fourth)
    connect(fourth, @opening)
    @opening.update!(mobile: true)
    @stub.update!(mobile: true)
    create(:world_mechanic, story: @story, name: "The nightly rearrangement")

    first = WorldSeed.dump(WorldSeed::Exporter.new(@story).document)

    @story.destroy!
    @universe.destroy!
    reloaded = WorldSeed::Loader.new(WorldSeed.parse(first)).load!

    assert_equal first, WorldSeed.dump(WorldSeed::Exporter.new(reloaded).document)
    assert_equal 2, reloaded.locations.mobile.count
    assert_equal "shuffle_connections", reloaded.world_mechanics.sole.kind
  end

  private

  def connect(from, to)
    create(:location_connection, :short_distance, location: from, connected_location: to)
  end
end
