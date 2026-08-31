require "test_helper"

class WorldSeed::ExporterTest < ActiveSupport::TestCase
  def setup
    @universe = create(:universe, race_names: [ "Elf", "Dwarf" ])
    @story = create(:story, universe: @universe, title: "A World To Export")
    @opening = create(:location, story: @story, name: "The Opening Room")
    @stub = create(:location, :stub, story: @story, name: "Somewhere Else")
    connect(@opening, @stub)
    connect(@stub, @opening)
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

  test "warns about the progress it does not export" do
    create(:scene, story: @story, location: @opening)
    create(:playthrough, story: @story)

    exporter = WorldSeed::Exporter.new(@story)
    exporter.document

    assert_includes exporter.warnings.join("\n"), "scene(s) not exported"
    assert_includes exporter.warnings.join("\n"), "playthrough(s) not exported"
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

  private

  def connect(from, to)
    create(:location_connection, :short_distance, location: from, connected_location: to)
  end
end
