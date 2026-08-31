require "test_helper"

class WorldSeed::LoaderTest < ActiveSupport::TestCase
  test "loads a world with no model call at all" do
    # Nothing in the seed path may reach an agent: seeding has to work with no
    # API key, no ollama and no network.
    BaseAgent.stub(:new, -> { flunk "loading a seed file asked a model something" }) do
      story = WorldSeed::Loader.new(document).load!

      assert_equal "A Seeded World", story.title
      assert_equal %w[Ashfolk Riverkin], story.universe.races.order(:name).pluck(:name)
      assert_equal [ "The Office", "The Closet", "The Hallway" ], story.locations.order(:id).pluck(:name)
      assert_equal "The Office", story.opening_location.name
    end
  end

  test "writes both directions of every connection" do
    story = WorldSeed::Loader.new(document).load!
    office, closet = story.locations.where(name: [ "The Office", "The Closet" ]).order(:id).to_a

    assert_equal [ "The Closet", "The Hallway" ], office.exits.order(:id).pluck(:name)
    assert_equal [ "The Office" ], closet.exits.pluck(:name)
    assert_equal 4, LocationConnection.where(location: story.locations).count
  end

  test "derives time_to_travel rather than reading it from the file" do
    story = WorldSeed::Loader.new(document).load!
    connection = LocationConnection.find_by(location: story.opening_location)

    assert_equal "about a minute", connection.time_to_travel
  end

  test "loading twice updates rather than duplicates" do
    WorldSeed::Loader.new(document).load!

    edited = document
    edited["story"]["genre"] = "revised genre"
    edited["locations"].first["description"] = "A revised office."

    assert_no_difference [ "Story.count", "Universe.count", "Race.count", "Location.count", "LocationConnection.count", "Character.count", "Item.count" ] do
      WorldSeed::Loader.new(edited).load!
    end

    story = Story.find_by(title: "A Seeded World")
    assert_equal "revised genre", story.genre
    assert_equal "A revised office.", story.opening_location.description
  end

  test "matches on natural keys, not ids" do
    first = WorldSeed::Loader.new(document).load!
    # A different world in between, so a second load cannot land on the same ids.
    create(:story)

    assert_equal first.id, WorldSeed::Loader.new(document).load!.id
  end

  test "loads a character with its race, protagonist flag and items" do
    story = WorldSeed::Loader.new(document).load!
    character = story.characters.sole

    assert_equal "Vesper Aal", character.fullname
    assert_equal "Riverkin", character.race.name
    assert_equal story, character.race.universe.stories.first
    assert character.is_protagonist?
    assert_equal story, story.protagonist.story
    assert_equal [ "A Daybook" ], character.items.pluck(:name)
  end

  test "rejects a file it does not understand" do
    error = assert_raises(WorldSeed::Loader::InvalidWorld) do
      WorldSeed::Loader.new(document.merge("format" => 99)).load!
    end

    assert_match(/unknown format 99/, error.message)
  end

  test "rejects a world with no single opening location" do
    without_opening = document
    without_opening["locations"].each { |location| location.delete("opening") }

    assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(without_opening).load! }
  end

  test "rejects a world whose opening location is a stub, because it cannot be played" do
    stub_opening = document
    stub_opening["locations"].first["detail_level"] = "stub"

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(stub_opening).load! }
    assert_match(/must be realized/, error.message)
  end

  test "rejects a connection to a location the file does not declare" do
    dangling = document
    dangling["connections"] << { "between" => [ "The Office", "The Roof" ], "distance" => "adjacent", "travel_method" => "walking" }

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(dangling).load! }
    assert_match(/The Roof/, error.message)
  end

  test "rejects a character whose race is not in this universe" do
    wrong_race = document
    wrong_race["characters"].first["race"] = "Elf"

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(wrong_race).load! }
    assert_match(/Elf/, error.message)
  end

  test "leaves nothing behind when a world fails half way through" do
    invalid = document
    invalid["connections"].first["distance"] = "a distance no fixed table has"

    assert_no_difference [ "Story.count", "Universe.count", "Location.count" ] do
      assert_raises(ActiveRecord::RecordInvalid) { WorldSeed::Loader.new(invalid).load! }
    end
  end

  test "names the file it is complaining about" do
    error = assert_raises(WorldSeed::Loader::InvalidWorld) do
      WorldSeed::Loader.new(document.merge("format" => 0), source: "db/seeds/worlds/broken.yml").load!
    end

    assert_match(/broken\.yml/, error.message)
  end

  private

  # Built fresh on every call so a test can edit it without touching another's.
  def document
    WorldSeed.parse(WorldSeed.dump(
      "format" => WorldSeed::FORMAT,
      "universe" => {
        "physics" => "Ordinary physics, ordinarily applied.",
        "technology" => "Steam, paper and pneumatic tubes.",
        "weapons" => "Batons, and the paperwork to justify one.",
        "geographies" => "A river delta, a levee, and the high ground behind it.",
        "civilizations" => "One city, one institution, and everybody else.",
        "history" => "A flood survey that never stopped surveying.",
        "economics" => "Wages in coin, standing in the record.",
        "politics" => "Whoever can make a document exist.",
        "religion" => "The world as a document being transcribed.",
        "races" => [
          { "name" => "Riverkin", "description" => "Delta-born, and unimpressed by paperwork." },
          { "name" => "Ashfolk", "description" => "Kept the records after the fire, and never gave them back." }
        ]
      },
      "story" => {
        "title" => "A Seeded World",
        "genre" => "bureaucratic mystery",
        "start_time" => "2026-08-31T18:40:00Z",
        "preface" => "An hour is missing out of the middle of your own daybook.",
        "summary" => "A clerk works out what happened in an hour nobody wrote down."
      },
      "characters" => [
        {
          "fullname" => "Vesper Aal", "race" => "Riverkin", "nickname" => "Vesp", "age" => 41,
          "sex" => "female", "is_protagonist" => true, "is_companion" => false,
          "backstory" => "Eleven years at the same desk, by request.",
          "personality" => "Precise, dry, unhurried.", "appearance" => "Upright, greying, ink to the knuckle.",
          "likes" => "A ledger that balances", "dislikes" => "Amendments in another hand",
          "fears" => "Signing something that closed a file",
          "items" => [ { "name" => "A Daybook", "description" => "Eleven years of her own handwriting.", "properties" => '{"registered": true}' } ]
        }
      ],
      "locations" => [
        { "name" => "The Office", "detail_level" => "realized", "opening" => true,
          "teaser" => "Two desks and one missing hour.", "description" => "An office.", "lore" => "It has always been four clerks on paper." },
        { "name" => "The Closet", "detail_level" => "realized",
          "teaser" => "No inventory number.", "description" => "A closet, and no other door.", "lore" => "Shelved out in the wrong order." },
        { "name" => "The Hallway", "detail_level" => "stub", "teaser" => "Doors closing, one after another." }
      ],
      "connections" => [
        { "between" => [ "The Office", "The Closet" ], "distance" => "adjacent", "travel_method" => "walking" },
        { "between" => [ "The Office", "The Hallway" ], "distance" => "adjacent", "travel_method" => "walking" }
      ]
    ))
  end
end
