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

    assert_no_difference [ "Story.count", "Universe.count", "Race.count", "Location.count", "LocationConnection.count", "Character.count", "Item.count", "Scene.count" ] do
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

  # WHAT IS LYING IN A ROOM, which is the closed set `take` resolves against and
  # the only way a world can carry anything takeable at all.
  test "loads an item lying in a location, in the room and in nobody's hands" do
    story = WorldSeed::Loader.new(document).load!
    closet = story.locations.find_by(name: "The Closet")
    index = closet.items.sole

    assert_equal "A Private Index", index.name
    assert_predicate index, :lying?
    assert_nil index.character
    assert_equal [ index ], Item.lying_in(closet).to_a
  end

  # THE KEY IS (story, name) AND NOT THE OWNER, because an item moves: `take`
  # and `drop` write the very columns the file declares. A file keyed on the
  # owner would look for the daybook in the hands it declares, miss the one the
  # player left on a shelf, and seed a second daybook.
  test "re-seeding a played world moves its items back rather than duplicating them" do
    story = WorldSeed::Loader.new(document).load!
    daybook = story.characters.sole.items.sole
    closet = story.locations.find_by(name: "The Closet")

    # The player picks the index up and puts the daybook down, which is exactly
    # what `Playthrough::Turn#carry!` and `#put_down!` write.
    daybook.update!(character: nil, location: closet)
    closet.items.find_by(name: "A Private Index").update!(character: story.protagonist, location: nil)

    WorldSeed::Loader.new(document).load!

    assert_equal [ daybook.id ], story.protagonist.reload.items.pluck(:id)
    assert_equal [ "A Private Index" ], closet.reload.items.pluck(:name)
    assert_equal 2, Item.where(id: story.protagonist.item_ids + closet.item_ids).count
  end

  test "rejects a file with the same item name twice" do
    twice = document
    twice["locations"].last["items"] = [ { "name" => "A Daybook", "description" => "The wrong one.", "properties" => "{}" } ]

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(twice).load! }

    assert_match(/duplicate item names: a daybook/, error.message)
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

  # The one Scene that is world rather than progress. The seed carries it so the
  # player reads a narrated arrival on the first screen with no model call
  # behind it, and so somebody is standing in the opening room to talk to.
  test "loads the opening arrival with its cast" do
    story = WorldSeed::Loader.new(document).load!
    scene = story.opening_scene

    assert scene.present?
    assert scene.is_opening?
    assert_equal "The Office", scene.location.name
    assert_equal "You are still holding the stamp when the hallway goes quiet.", scene.description
    assert_equal [ "Vesper Aal" ], scene.characters.pluck(:fullname)
    assert_nil scene.previous_scene
  end

  # An opening arrival happens at the moment the story begins, and the world
  # already carries that moment. Restating it in the file would be a second
  # place to edit and a second place to drift.
  test "the opening arrival is stamped with the story's start time" do
    story = WorldSeed::Loader.new(document).load!

    assert_equal story.start_time, story.opening_scene.story_timestamp
  end

  # Seeding a world is not somebody standing in a room. See Scene and
  # PlaythroughsController#create.
  test "loading an opening arrival does not mark the opening room as visited" do
    story = WorldSeed::Loader.new(document).load!

    assert_nil story.opening_location.last_protagonist_visit
  end

  # This is the payoff, and it is the reason the opening arrival is world data
  # rather than something a playthrough invents: `characters_present` reads the
  # last scene in a location that recorded anyone, so a seeded world with a cast
  # in its opening scene has somebody to talk to on turn one. Without it the
  # answer is the protagonist alone and Playthrough::Classifier offers no one.
  test "a seeded world has somebody standing in the opening room" do
    story = WorldSeed::Loader.new(document).load!

    assert_equal [ "Vesper Aal" ],
                 Scene::Generator.characters_present(story.opening_location).map(&:fullname)
  end

  test "rejects a world with no opening arrival" do
    without = document
    without.delete("opening_scene")

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(without).load! }
    assert_match(/needs an `opening_scene`/, error.message)
  end

  test "rejects an opening arrival somewhere other than the opening location" do
    elsewhere = document
    elsewhere["opening_scene"]["location"] = "The Closet"

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(elsewhere).load! }
    assert_match(/the story opens in "The Office"/, error.message)
  end

  test "rejects an opening arrival casting somebody the file does not declare" do
    ghost = document
    ghost["opening_scene"]["characters"] << "Nobody At All"

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(ghost).load! }
    assert_match(/Nobody At All/, error.message)
  end

  # --- a world's own mechanics ---------------------------------------------

  test "loads a world's mechanics, and never a last_run_at" do
    story = WorldSeed::Loader.new(with_mechanic).load!
    mechanic = story.world_mechanics.sole

    assert_equal "The nightly rearrangement", mechanic.name
    assert_equal "shuffle_connections", mechanic.kind
    assert_equal "nightly", mechanic.cadence
    assert_match "Nocturna", mechanic.description
    assert_nil mechanic.last_run_at, "how far a mechanic has got is progress, not world"
  end

  test "loads which locations move" do
    story = WorldSeed::Loader.new(with_mechanic).load!

    assert_equal [ "The Closet", "The Office" ], story.locations.mobile.order(:name).pluck(:name)
    assert_equal [ "The Hallway" ], story.locations.anchored.pluck(:name)
  end

  test "a world with no mechanics loads, and moves not at all" do
    story = WorldSeed::Loader.new(document).load!

    assert_empty story.world_mechanics
    assert_empty story.locations.mobile
  end

  test "loading a mechanic twice updates rather than duplicates" do
    WorldSeed::Loader.new(with_mechanic).load!

    edited = with_mechanic
    edited["mechanics"].first["cadence"] = "weekly"

    assert_no_difference -> { WorldMechanic.count } do
      WorldSeed::Loader.new(edited).load!
    end

    assert_equal "weekly", Story.find_by(title: "A Seeded World").world_mechanics.sole.cadence
  end

  test "rejects a mechanic whose kind is not in the catalogue" do
    broken = with_mechanic
    broken["mechanics"].first["kind"] = "rain_frogs"

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(broken).load! }
    assert_match(/rain_frogs/, error.message)
  end

  test "rejects a mechanic whose cadence is not one of the cadences" do
    broken = with_mechanic
    broken["mechanics"].first["cadence"] = "fortnightly"

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(broken).load! }
    assert_match(/fortnightly/, error.message)
  end

  test "rejects a nameless mechanic, because the name is the key re-seeding matches on" do
    broken = with_mechanic
    broken["mechanics"].first.delete("name")

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(broken).load! }
    assert_match(/needs a `name`/, error.message)
  end

  test "rejects two mechanics with the same name" do
    broken = with_mechanic
    broken["mechanics"] << broken["mechanics"].first.dup

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(broken).load! }
    assert_match(/duplicate mechanic names/, error.message)
  end

  # THE HAND-EDIT THAT WOULD OTHERWISE PASS SILENTLY: a world that says it
  # rearranges itself every night, with nothing in it that can move. It loads,
  # it plays, and the thing it promises never happens.
  test "rejects a shuffle with nothing to shuffle" do
    broken = with_mechanic
    broken["locations"].each { |location| location.delete("mobile") }

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(broken).load! }
    assert_match(/0 connection\(s\)/, error.message)
    assert_match(/at least two/, error.message)
  end

  # One edge is not two: there is nothing for the endpoint to be swapped with, so
  # the shuffle would be a no-op every night.
  test "rejects a shuffle with only one edge out of the mobile part of the world" do
    broken = with_mechanic
    broken["locations"].detect { |location| location["name"] == "The Closet" }.delete("mobile")
    broken["connections"].reject! { |edge| edge["between"] == [ "The Office", "The Hallway" ] }

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(broken).load! }
    assert_match(/1 connection\(s\)/, error.message)
  end

  test "names the file it is complaining about" do
    error = assert_raises(WorldSeed::Loader::InvalidWorld) do
      WorldSeed::Loader.new(document.merge("format" => 0), source: "db/seeds/worlds/broken.yml").load!
    end

    assert_match(/broken\.yml/, error.message)
  end

  private

  # The same world with a hand-written mechanic: the office and the closet travel
  # together, the hallway is fixed ground, so both edges to the hallway are
  # shufflable.
  def with_mechanic
    edited = document
    edited["locations"].detect { |location| location["name"] == "The Office" }["mobile"] = true
    edited["locations"].detect { |location| location["name"] == "The Closet" }["mobile"] = true
    edited["connections"] << { "between" => [ "The Closet", "The Hallway" ], "distance" => "adjacent", "travel_method" => "walking" }
    edited["mechanics"] = [
      { "name" => "The nightly rearrangement", "kind" => "shuffle_connections", "cadence" => "nightly",
        "description" => "Nocturna floods the ward at midnight and the rooms come back in another order." }
    ]
    edited
  end

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
      "opening_scene" => {
        "location" => "The Office",
        "characters" => [ "Vesper Aal" ],
        "description" => "You are still holding the stamp when the hallway goes quiet.",
        "summary" => "The clerk notices the gap in the daybook."
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
          "teaser" => "No inventory number.", "description" => "A closet, and no other door.", "lore" => "Shelved out in the wrong order.",
          "items" => [ { "name" => "A Private Index", "description" => "Two columns in a hand that is not hers.", "properties" => '{"registered": false}' } ] },
        { "name" => "The Hallway", "detail_level" => "stub", "teaser" => "Doors closing, one after another." }
      ],
      "connections" => [
        { "between" => [ "The Office", "The Closet" ], "distance" => "adjacent", "travel_method" => "walking" },
        { "between" => [ "The Office", "The Hallway" ], "distance" => "adjacent", "travel_method" => "walking" }
      ]
    ))
  end
end
