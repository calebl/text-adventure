# A WORLD, AND THEN SOMEBODY PLAYING IT -- the two halves `Story::Fork` has to
# tell apart, built here once so the snapshot, the derivation and the fork tests
# all argue about the same records.
#
# `#seeded_world` loads a document through `WorldSeed::Loader`, which is exactly
# how the captain's three checked-in worlds come to exist. `#play!` then does to
# it what play does: a playthrough, scenes that are not the opening arrival,
# verdicts on them, and the rooms and people a realization writes -- all stamped
# AFTER the playthrough, because that is the line the derivation reads.
module ForkableWorld
  # Where the derivation draws its line. The world is stamped before it and
  # everything `#play!` writes is stamped after, so a test never depends on how
  # fast it runs.
  GENERATED_AT = Time.utc(2026, 1, 1, 9, 0, 0)
  PLAY_STARTED_AT = Time.utc(2026, 1, 2, 9, 0, 0)

  def seeded_world(document = world_document)
    story = travel_to(GENERATED_AT) { WorldSeed::Loader.new(document).load! }
    # `WorldSeed::Loader` writes the world in one transaction, and SQLite stamps
    # every row in it with the frozen clock above -- including the opening
    # arrival, which is the one Scene that is world.
    story
  end

  # ONE PLAYTHROUGH, TWO TURNS AND A VERDICT, plus the room and the person a
  # realization would have written. Returns the playthrough.
  def play!(story)
    travel_to(PLAY_STARTED_AT) do
      playthrough = create(:playthrough, story: story, character: story.protagonist)
      opening = story.opening_location
      turn = create(:scene, story: story, location: opening, story_timestamp: story.start_time + 5.minutes)
      create(:playthrough_feedback, playthrough: playthrough, scene: turn, verdict: "good")

      # WHAT A REALIZATION DOES, which is the half the derivation has to leave
      # behind: the room play walked into becomes realized, invents a neighbour,
      # and gets a cast and a thing lying in it.
      hallway = story.locations.find_by(name: "The Hallway")
      hallway.update!(detail_level: :realized, description: "A hallway, at last.", lore: "Nobody has ever cleaned it.")
      stairs = create(:location, :stub, story: story, name: "The Stairs", teaser: "Down, probably.")
      [ [ hallway, stairs ], [ stairs, hallway ] ].each do |from, to|
        create(:location_connection, location: from, connected_location: to, distance: "adjacent", travel_method: "walking")
      end
      create(:character, story: story, fullname: "Someone Play Made", location: hallway,
                         race: story.universe.races.first)
      create(:item, name: "a thing play made", location: hallway, character: nil)

      playthrough
    end
  end

  def world_document
    WorldSeed.parse(WorldSeed.dump(
      "format" => WorldSeed::FORMAT,
      "universe" => {
        "physics" => "Ordinary physics, ordinarily applied.",
        "technology" => "Steam, paper and pneumatic tubes.",
        "weapons" => "Batons, and the paperwork to justify one.",
        "geographies" => "A river delta and the high ground behind it.",
        "civilizations" => "One city and one institution.",
        "history" => "A flood survey that never stopped surveying.",
        "economics" => "Wages in coin, standing in the record.",
        "politics" => "Whoever can make a document exist.",
        "religion" => "The world as a document being transcribed.",
        "races" => [
          { "name" => "Riverkin", "description" => "Delta-born, and unimpressed by paperwork." }
        ]
      },
      "story" => {
        "title" => "A Forkable World",
        "genre" => "bureaucratic mystery",
        "start_time" => "2026-01-01T09:00:00Z",
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
          "stats" => { "level" => 3, "hit_die" => 8, "strength" => 10, "dexterity" => 11, "will" => 13 },
          "backstory" => "Eleven years at the same desk, by request.",
          "personality" => "Precise, dry, unhurried.", "appearance" => "Upright, greying, ink to the knuckle.",
          "likes" => "A ledger that balances", "dislikes" => "Amendments in another hand",
          "fears" => "Signing something that closed a file",
          "items" => [ { "name" => "A Daybook", "description" => "Eleven years of her own handwriting.", "properties" => "{}" } ]
        },
        {
          "fullname" => "Corbel Ashe", "race" => "Riverkin", "location" => "The Office", "nickname" => "Corbel",
          "age" => 33, "sex" => "male", "is_protagonist" => false, "is_companion" => false,
          "stats" => { "level" => 1, "hit_die" => 6, "strength" => 9, "dexterity" => 10, "will" => 12 },
          "backstory" => "Kept the records after the fire.", "personality" => "Watchful and unhurried.",
          "appearance" => "Soot at the cuff, whatever he is wearing.",
          "likes" => "A shelf in the right order", "dislikes" => "Being asked twice",
          "fears" => "A door with no inventory number"
        }
      ],
      "locations" => [
        { "name" => "The Office", "detail_level" => "realized", "opening" => true,
          "teaser" => "Two desks and one missing hour.", "description" => "An office.",
          "lore" => "It has always been four clerks on paper.",
          "items" => [ { "name" => "A Stamp", "description" => "Worn smooth on one edge.", "properties" => "{}" } ] },
        { "name" => "The Hallway", "detail_level" => "stub", "teaser" => "Doors closing, one after another." }
      ],
      "connections" => [
        { "between" => [ "The Office", "The Hallway" ], "distance" => "adjacent", "travel_method" => "walking" }
      ]
    ))
  end
end
