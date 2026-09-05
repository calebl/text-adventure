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
    character = story.protagonist

    assert_equal "Vesper Aal", character.fullname
    assert_equal "Riverkin", character.race.name
    assert_equal story, character.race.universe.stories.first
    assert character.is_protagonist?
    assert_equal story, story.protagonist.story
    assert_equal [ "A Daybook" ], character.items.pluck(:name)
  end

  # --- the stat block, which a hand-authored world IS the decision about ------

  # `WorldSeed::Loader::STAT_KEYS` is all five: the level, the hit die and the
  # three abilities. A whole sheet, because that is what the file carries or
  # nothing.
  def sheet(level: 1, hit_die: 8, strength: 12, dexterity: 10, will: 14)
    { "level" => level, "hit_die" => hit_die, "strength" => strength,
      "dexterity" => dexterity, "will" => will }
  end

  test "loads a character's stat block when the file gives one" do
    world = document
    world["characters"].first["stats"] = sheet(level: 2, hit_die: 10)

    character = WorldSeed::Loader.new(world).load!.protagonist

    assert_equal [ 2, 10 ], [ character.level, character.hit_die ]
    assert_equal 16, character.max_hp
  end

  # THE ABILITIES ARE THE FILE'S DECISION TOO, and they are not part of
  # `#max_hp`: the captain's ruling that the body's capacity is the hit die and
  # nothing else. This is that stated as a test -- the maximum for a d10 at
  # level 2 is 16 whatever the will says.
  test "loads a character's three abilities, and none of them touches the maximum" do
    world = document
    world["characters"].first["stats"] = sheet(level: 2, hit_die: 10, strength: 7, dexterity: 15, will: 18)

    character = WorldSeed::Loader.new(world).load!.protagonist

    assert_equal [ 7, 15, 18 ], [ character.strength, character.dexterity, character.will ]
    assert_predicate character, :abilities?
    assert_equal 16, character.max_hp
  end

  # NOTHING IS ROLLED ON LOAD. A file that says nothing about a body leaves the
  # columns exactly as they are, so a re-seed cannot quietly rewrite a world
  # because somebody edited a different part of the file.
  test "a character the file gives no stats to gets none" do
    character = WorldSeed::Loader.new(document).load!.protagonist

    assert_not_predicate character, :stat_block?
    assert_not_predicate character, :abilities?
  end

  test "re-seeding re-asserts the file's whole sheet over a played world" do
    world = document
    world["characters"].first["stats"] = sheet(hit_die: 10, strength: 15)
    story = WorldSeed::Loader.new(world).load!
    story.protagonist.update!(hit_die: 6, strength: 3)

    WorldSeed::Loader.new(world).load!

    assert_equal [ 10, 15 ], [ story.protagonist.reload.hit_die, story.protagonist.strength ]
  end

  # ALL FIVE KEYS OR NONE. The record refuses the two halves separately; the FILE
  # is held to the whole sheet, because a hand-authored world is the decision and
  # a half-authored one is an editing slip.
  test "rejects a stats mapping with only some of the five keys" do
    [ { "level" => 1 }, { "level" => 1, "hit_die" => 8 },
      { "level" => 1, "hit_die" => 8, "strength" => 12 } ].each do |partial|
      world = document
      world["characters"].first["stats"] = partial

      error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(world).load! }
      assert_match(/all of them together or none/, error.message)
    end
  end

  test "rejects a hit die the engine would never roll" do
    world = document
    world["characters"].first["stats"] = sheet(hit_die: 7)

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(world).load! }
    assert_match(/hit die 7/, error.message)
  end

  test "rejects a level outside the declared range" do
    world = document
    world["characters"].first["stats"] = sheet(level: 0)

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(world).load! }
    assert_match(/level 0/, error.message)
  end

  # 3d6 CANNOT COME UP 2 OR 19, so a number outside `Character::ABILITY_RANGE`
  # came from somewhere that is not the engine -- and the file's error names the
  # person and the ability, which is what somebody editing YAML needs.
  test "rejects an ability outside the range 3d6 rolls" do
    [ [ :strength, 19 ], [ :dexterity, 2 ], [ :will, 0 ] ].each do |ability, score|
      world = document
      world["characters"].first["stats"] = sheet(**{ ability => score })

      error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(world).load! }
      assert_match(/#{ability} #{score}/, error.message)
    end
  end

  # WHAT IS LYING IN A ROOM, which is the closed set `take` resolves against and
  # the only way a world can carry anything takeable at all.
  # --- a world that contains an enemy ---------------------------------------

  test "loads a monstrous race and a hostile character straight through" do
    world = document
    world["universe"]["races"] << { "name" => "Nocturna-Blighted", "monstrous" => true,
                                    "description" => "What is left when somebody stands too long under the glow." }
    world["characters"] << monster

    story = WorldSeed::Loader.new(world).load!
    marek = story.characters.find_by(fullname: "Marek Sollen")

    assert_predicate story.universe.races.find_by(name: "Nocturna-Blighted"), :monstrous?
    assert_predicate marek, :hostile?
    assert_equal [ marek ], story.playthroughs.new.foes_in(story.locations.find_by(name: "The Closet"))
  end

  test "a race the file says nothing about is a people, and a character it says nothing about is not hostile" do
    story = WorldSeed::Loader.new(document).load!

    assert_equal [], story.universe.monstrous_races.to_a
    assert_equal [], story.characters.hostile.to_a
  end

  # A RACE THAT ALREADY EXISTS AND CHANGED IS WRITTEN BACK. It was not, before
  # the monstrous flag needed it to be: `has_many` saves the new records in a
  # collection and leaves the changed ones alone, so editing a race's
  # description in a seed file and re-seeding did nothing at all.
  test "re-seeding writes an edited race description back" do
    WorldSeed::Loader.new(document).load!

    edited = document
    edited["universe"]["races"].first["description"] = "Delta-born, and done being unimpressed."
    story = WorldSeed::Loader.new(edited).load!

    assert_equal "Delta-born, and done being unimpressed.",
                 story.universe.races.find_by(name: "Riverkin").description
  end

  # THE FILE IS THE DECISION AND IT RE-ASSERTS ITSELF, in both directions. A
  # world that disarms its monster and is re-seeded has a disarmed monster --
  # which a flag only ever written one way could never do.
  test "re-seeding takes hostility and monstrousness off when the file drops them" do
    armed = document
    armed["universe"]["races"] << { "name" => "Nocturna-Blighted", "monstrous" => true,
                                    "description" => "What is left when somebody stands too long under the glow." }
    armed["characters"] << monster
    WorldSeed::Loader.new(armed).load!

    disarmed = document
    disarmed["universe"]["races"] << { "name" => "Nocturna-Blighted", "monstrous" => false,
                                       "description" => "What is left when somebody stands too long under the glow." }
    disarmed["characters"] << monster.merge("hostile" => false)
    story = WorldSeed::Loader.new(disarmed).load!

    assert_not_predicate story.characters.find_by(fullname: "Marek Sollen"), :hostile?
    assert_not_predicate story.universe.races.find_by(name: "Nocturna-Blighted"), :monstrous?
  end

  test "rejects a hostile character with no body" do
    world = document
    world["universe"]["races"] << { "name" => "Nocturna-Blighted", "monstrous" => true,
                                    "description" => "What is left when somebody stands too long under the glow." }
    world["characters"] << monster.except("stats")

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(world).load! }
    assert_match(/a foe needs a body/, error.message)
  end

  test "loads a room's danger and defaults the rest to safe" do
    world = document
    world["locations"].find { |room| room["name"] == "The Closet" }["danger"] = "dangerous"

    story = WorldSeed::Loader.new(world).load!

    assert_equal "dangerous", story.locations.find_by(name: "The Closet").danger
    assert_equal Location::SAFE, story.locations.find_by(name: "The Office").danger
    assert_predicate story.locations.find_by(name: "The Closet"), :dangerous?
  end

  # THE SAME BOTH-DIRECTIONS RULE, one table over: a stale "dangerous" would
  # keep a world writing monsters into a room its author had made safe.
  test "re-seeding takes a room's danger off when the file drops it" do
    dangerous = document
    dangerous["locations"].find { |room| room["name"] == "The Closet" }["danger"] = "deadly"
    WorldSeed::Loader.new(dangerous).load!

    story = WorldSeed::Loader.new(document).load!

    assert_equal Location::SAFE, story.locations.find_by(name: "The Closet").danger
  end

  test "rejects a danger the engine has no table for" do
    world = document
    world["locations"].first["danger"] = "a bit worrying"

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(world).load! }
    assert_match(/there is: safe, uneasy, dangerous, deadly/, error.message)
  end

  def monster
    {
      "fullname" => "Marek Sollen", "race" => "Nocturna-Blighted", "location" => "The Closet",
      "hostile" => true, "stats" => sheet(hit_die: 10, strength: 14, dexterity: 8, will: 3),
      "nickname" => "the Ringer", "age" => 44, "sex" => "male",
      "is_protagonist" => false, "is_companion" => false,
      "backstory" => "He rang the hour for twenty-nine years.", "personality" => "Habit, and a terrible steadiness.",
      "appearance" => "Grey all the way through, and far too still.",
      "likes" => "The hour", "dislikes" => "A name said out loud",
      "fears" => "Nothing at all"
    }
  end

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
    daybook = story.protagonist.items.sole
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

  # THE FILE RE-ASSERTS ITSELF OVER THE WORLD LAYER AND REACHES NO GAME AT ALL.
  # It used to reach into a party's hands, because before the captain's ruling
  # of 2026-09-04 a room item somebody had picked up WAS the world's only row --
  # so putting the room back meant taking the thing off the player. Now the
  # world's own row never left the closet, so re-seeding has nothing to take
  # back, and the copy in her hands is hers.
  test "re-seeding puts nothing back because the world's own row never moved, and leaves the party's copy alone" do
    story = WorldSeed::Loader.new(document).load!
    closet = story.locations.find_by(name: "The Closet")
    played = create(:playthrough, story: story, character: story.protagonist, current_location: closet)
    template = closet.items.templates.find_by(name: "A Private Index")
    copy = played.items_lying_in(closet).find_by(name: "A Private Index")
    Playthrough::Turn.new(played).send(:carry!, copy)

    WorldSeed::Loader.new(document).load!

    assert_equal closet, template.reload.location
    assert_predicate template, :template?
    assert_predicate copy.reload, :carried?
    assert_equal played, copy.playthrough
    assert_equal [ "A Private Index" ], closet.reload.items.templates.pluck(:name)
  end

  # THE FILE OWNS THE STARTING INVENTORY AND NOT A PLAYER'S COPY OF IT. Every
  # playthrough carries its own copy of what the story starts the player with,
  # so `#find_item` searches the world's own rows first: re-asserting the file
  # onto a copy would take the daybook out of one player's hands and leave the
  # world's row wherever it was.
  test "re-seeding leaves each party's copy of the starting inventory alone" do
    story = WorldSeed::Loader.new(document).load!
    played = create(:playthrough, story: story, character: story.protagonist)
    copy = played.carried.sole

    WorldSeed::Loader.new(document).load!

    assert_equal [ "A Daybook" ], story.protagonist.reload.items.pluck(:name)
    assert_equal copy, played.carried.sole
    assert_equal played, copy.reload.playthrough
  end

  # WHAT IS WRITTEN ON A THING, carried by the file. A seeded room is realized by
  # the file rather than by a model call, so what a note in one says is whatever
  # the file says and nothing else -- and `Item::Inscriber` never runs for it.
  test "loads what is written on a readable thing" do
    written = document
    written["locations"].find { |place| place["name"] == "The Closet" }["items"].first.merge!(
      "readable" => true, "inscription" => "19 Thaw — 1188/12 — QUERY RAISED"
    )

    story = WorldSeed::Loader.new(written).load!
    index = story.locations.find_by(name: "The Closet").items.sole

    assert index.readable?
    assert index.inscribed?
    assert_equal "19 Thaw — 1188/12 — QUERY RAISED", index.inscription
  end

  test "a thing the file says nothing about has no writing on it" do
    story = WorldSeed::Loader.new(document).load!

    assert_not story.locations.find_by(name: "The Closet").items.sole.readable?
  end

  # `Item` refuses the pair the other way round inside the same transaction, so
  # the file would not load either way. This names the file and the item, which
  # is what somebody editing YAML needs.
  test "rejects an inscription on a thing the file did not mark readable" do
    bad = document
    bad["locations"].find { |place| place["name"] == "The Closet" }["items"].first["inscription"] = "Words on nothing."

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(bad).load! }

    assert_match(/A Private Index/, error.message)
    assert_match(/readable: true/, error.message)
  end

  test "rejects a file with the same item name twice" do
    twice = document
    twice["locations"].last["items"] = [ { "name" => "A Daybook", "description" => "The wrong one.", "properties" => "{}" } ]

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(twice).load! }

    assert_match(/one name to a re-seed/, error.message)
    assert_match(/A Daybook/, error.message)
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

  # --- re-seeding a world somebody has played --------------------------------
  #
  # THE DEFECT THESE PIN. `WorldSeed::Loader` adds and never reconciled, so
  # re-seeding a played world could leave it with two of something: two rooms
  # because the file's name for one had been edited, two items for the same
  # reason, and a second doorway off every mobile room because the world's own
  # nightly shuffle had moved the first one. See the class header.

  test "a room the file renamed is the same room, renamed" do
    story = WorldSeed::Loader.new(document).load!
    closet = story.locations.find_by(name: "The Closet")
    closet.update!(last_protagonist_visit: story.start_time)

    renamed = document
    renamed["locations"].detect { |row| row["name"] == "The Closet" }["name"] = "Closet"
    renamed["connections"].each { |row| row["between"] = row["between"].map { |name| name == "The Closet" ? "Closet" : name } }
    renamed["characters"].each { |row| row["location"] = "Closet" if row["location"] == "The Closet" }
    loader = WorldSeed::Loader.new(renamed)

    assert_no_difference [ "Location.count", "LocationConnection.count" ] do
      loader.load!
    end

    assert_equal "Closet", closet.reload.name
    assert_equal story.start_time, closet.last_protagonist_visit, "the row kept everything hanging off it"
    assert_equal [ "The Office" ], closet.exits.pluck(:name)
    assert_match(/renamed rather than a second location created beside it/, loader.reconciled.join("\n"))
  end

  test "an item the file renamed is the same item, renamed" do
    story = WorldSeed::Loader.new(document).load!
    index = Item.in_story(story).find_by(name: "A Private Index")

    renamed = document
    renamed["locations"].detect { |row| row["name"] == "The Closet" }["items"].first["name"] = "a PRIVATE index"
    loader = WorldSeed::Loader.new(renamed)

    assert_no_difference -> { Item.count } do
      loader.load!
    end

    assert_equal "a PRIVATE index", index.reload.name
    assert_equal story.locations.find_by(name: "The Closet"), index.location
    assert_match(/renamed rather than a second item created beside it/, loader.reconciled.join("\n"))
  end

  # A rename `WorldSeed.natural_key` cannot see is, to any loader, a row that
  # does not exist yet -- so it is created, and SAID OUT LOUD rather than
  # resolved: nothing in the file says which room it replaced.
  test "a rename nothing can recognize is created and warned about" do
    story = WorldSeed::Loader.new(document).load!
    create(:playthrough, story: story, current_location: story.opening_location)

    renamed = document
    renamed["locations"].detect { |row| row["name"] == "The Closet" }["name"] = "The Broom Cupboard"
    renamed["connections"].each { |row| row["between"] = row["between"].map { |name| name == "The Closet" ? "The Broom Cupboard" : name } }
    renamed["characters"].each { |row| row["location"] = "The Broom Cupboard" if row["location"] == "The Closet" }
    loader = WorldSeed::Loader.new(renamed)

    assert_difference -> { Location.count }, 1 do
      loader.load!
    end

    assert_match(/created location "The Broom Cupboard"/, loader.warnings.join("\n"))
    assert_match(/rake game:doctor/, loader.warnings.join("\n"))
  end

  test "a first seed warns about nothing at all" do
    loader = WorldSeed::Loader.new(document)
    loader.load!

    assert_empty loader.warnings
    assert_empty loader.reconciled
  end

  test "a world nobody has played is not warned about" do
    WorldSeed::Loader.new(document).load!

    renamed = document
    renamed["locations"] << { "name" => "The Yard", "detail_level" => "stub", "teaser" => "Rain off the levee." }
    renamed["connections"] << { "between" => [ "The Office", "The Yard" ], "distance" => "adjacent", "travel_method" => "walking" }
    loader = WorldSeed::Loader.new(renamed)
    loader.load!

    assert_empty loader.warnings, "a world with no playthroughs and no turns can be dropped and rebuilt"
  end

  # THE PHANTOM DOORWAY. `WorldMechanic::ShuffleConnections` repoints the far
  # end of a mobile room's doorway and preserves the count, so re-asserting the
  # file's own pair gives the room a second one -- which a later night then
  # reports as having moved when a player standing there sees no such thing.
  test "a doorway the world's own mechanic moved is not re-asserted as a second one" do
    story = WorldSeed::Loader.new(with_shuffle).load!
    mechanic = story.world_mechanics.sole
    at = mechanic.next_boundary_after(story.start_time)

    assert mechanic.operation.run!(at), "the world did not move, so there is nothing to re-assert over"
    mechanic.update!(last_run_at: at)
    moved = doorways(story)

    loader = WorldSeed::Loader.new(with_shuffle)
    assert_no_difference -> { LocationConnection.count } do
      loader.load!
    end

    assert_equal moved, doorways(story), "the file was re-asserted over the arrangement the world had moved to"
    assert_match(/left .* opening where the world put it/, loader.reconciled.join("\n"))
  end

  test "a doorway that is genuinely missing is still written" do
    story = WorldSeed::Loader.new(with_shuffle).load!
    mechanic = story.world_mechanics.sole
    mechanic.update!(last_run_at: story.start_time + 1.day)
    closet = story.locations.find_by(name: "The Closet")
    yard = story.locations.find_by(name: "The Yard")
    LocationConnection.where(location: closet, connected_location: yard)
                      .or(LocationConnection.where(location: yard, connected_location: closet)).destroy_all

    assert_difference -> { LocationConnection.count }, 2 do
      WorldSeed::Loader.new(with_shuffle).load!
    end
  end

  # --- what the file's own shape has to be -----------------------------------

  test "rejects a file whose rooms are one room to a re-seed" do
    twice = document
    twice["locations"].detect { |row| row["name"] == "The Closet" }["name"] = "Closet"
    twice["connections"].each { |row| row["between"] = row["between"].map { |name| name == "The Closet" ? "Closet" : name } }
    twice["characters"].each { |row| row["location"] = "Closet" if row["location"] == "The Closet" }
    twice["locations"] << { "name" => "The Closet", "detail_level" => "stub", "teaser" => "The other one." }
    twice["connections"] << { "between" => [ "The Office", "The Closet" ], "distance" => "adjacent", "travel_method" => "walking" }

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(twice).load! }
    assert_match(/one name to a re-seed/, error.message)
    assert_match(/Closet \/ The Closet|The Closet \/ Closet/, error.message)
  end

  # PR 85's documented authoring rule, made a rule the loader keeps: two
  # shufflable edges off ONE mobile room are permuted among themselves, which
  # leaves the room opening onto the same places, which the mechanic refuses as
  # a no-op. Such a world loads, validates, plays, and never moves.
  test "rejects a shuffle whose edges all hang off one mobile location" do
    broken = document
    broken["locations"].detect { |row| row["name"] == "The Office" }["mobile"] = true
    broken["mechanics"] = [ { "name" => "The nightly rearrangement", "kind" => "shuffle_connections",
                              "cadence" => "nightly", "description" => "The ward comes back in another order." } ]

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(broken).load! }
    assert_match(/hangs off the same `mobile: true` location/, error.message)
    assert_match(/at least two mobile locations/, error.message)
  end

  # The world the shuffle can actually move: two mobile rooms with one doorway
  # each into two DIFFERENT anchored places, so there is an arrangement that
  # changes which places end up joined.
  def with_shuffle
    edited = document
    edited["locations"].detect { |row| row["name"] == "The Office" }["mobile"] = true
    edited["locations"].detect { |row| row["name"] == "The Closet" }["mobile"] = true
    edited["locations"] << { "name" => "The Yard", "detail_level" => "stub", "teaser" => "Rain off the levee." }
    edited["connections"] << { "between" => [ "The Closet", "The Yard" ], "distance" => "adjacent", "travel_method" => "walking" }
    edited["mechanics"] = [
      { "name" => "The nightly rearrangement", "kind" => "shuffle_connections", "cadence" => "nightly",
        "description" => "Nocturna floods the ward at midnight and the rooms come back in another order." }
    ]
    edited
  end

  # Every doorway in the story as unordered name pairs, so the two rows a
  # connection is stored as read as the one door they are.
  def doorways(story)
    LocationConnection.joins(:location).where(locations: { story_id: story.id })
                      .includes(:location, :connected_location)
                      .map { |row| [ row.location.name, row.connected_location.name ].sort }
                      .uniq.sort
  end

  # --- where the file puts people -------------------------------------------

  # `characters[].location` is the closed set `talk` resolves against, written
  # by the file. Without it a seeded world's cast exists nowhere and can only be
  # spoken to in whatever room the opening arrival's cast happened to name.
  test "a character is placed where the file says they stand" do
    story = WorldSeed::Loader.new(document).load!
    closet = story.locations.find_by(name: "The Closet")

    assert_equal [ "Corbel Ashe" ], Character.present_in(closet).pluck(:fullname)
    assert_equal closet, story.characters.find_by(fullname: "Corbel Ashe").location
  end

  # Nowhere is a real state and the file is allowed to mean it: `The Unrecorded
  # Hour` leaves Perrin Lasco nowhere because that world is about him having
  # been removed from it.
  test "a character the file does not place stays nowhere" do
    story = WorldSeed::Loader.new(document).load!

    assert_predicate story.characters.find_by(fullname: "Vesper Aal"), :nowhere?
  end

  # `absent: true` IS THE FILE SAYING IT MEANT NOWHERE. Without it, nowhere is
  # reported by `rake game:doctor` as somebody nobody can speak to -- which is
  # right for a character nobody placed and wrong for `The Unrecorded Hour`,
  # whose premise is that Perrin Lasco has been removed from the world.
  test "a character the file marks absent is nowhere on purpose" do
    marked = document
    marked["characters"].last.delete("location")
    marked["characters"].last["absent"] = true

    story = WorldSeed::Loader.new(marked).load!
    corbel = story.characters.find_by(fullname: "Corbel Ashe")

    assert_predicate corbel, :deliberately_absent?
    assert_predicate corbel, :absent?
    assert_nil corbel.location
  end

  # A missing key still means "nobody has said where they are", which is the
  # state the doctor reports. The marker is the only thing that means the other
  # one, so a file that does not carry it does not assert it.
  test "a character the file leaves unmarked is not absent on purpose" do
    story = WorldSeed::Loader.new(document).load!

    assert_not_predicate story.characters.find_by(fullname: "Vesper Aal"), :deliberately_absent?
  end

  # BOTH DIRECTIONS, on the same "the file re-asserts itself over a played
  # world" rule the placements, the connections and the items follow: deleting
  # the marker from the file and re-seeding takes it off the record.
  test "re-seeding without the marker clears it" do
    marked = document
    marked["characters"].last.delete("location")
    marked["characters"].last["absent"] = true
    story = WorldSeed::Loader.new(marked).load!
    corbel = story.characters.find_by(fullname: "Corbel Ashe")
    assert_predicate corbel, :deliberately_absent?

    WorldSeed::Loader.new(document).load!

    assert_not_predicate corbel.reload, :deliberately_absent?
    assert_equal "The Closet", corbel.location.name
  end

  # Re-seeding re-asserts the absence too, for the same reason it re-asserts a
  # placement: the file is the decision.
  test "re-seeding puts a character the file marks absent back to nowhere" do
    marked = document
    marked["characters"].last.delete("location")
    marked["characters"].last["absent"] = true
    story = WorldSeed::Loader.new(marked).load!
    corbel = story.characters.find_by(fullname: "Corbel Ashe")
    corbel.move_to!(story.locations.find_by(name: "The Hallway"))

    WorldSeed::Loader.new(marked).load!

    assert_predicate corbel.reload, :absent?
  end

  # A file that means both things at once, and the record cannot hold both: the
  # marker says nobody may be offered this person to talk to and the location
  # says they are in that room's closed set.
  test "rejects a character the file marks absent and also places" do
    contradictory = document
    contradictory["characters"].last["absent"] = true

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(contradictory).load! }
    assert_match(/Corbel Ashe.*`absent: true` and also placed in "The Closet"/, error.message)
  end

  # An item is matched on (story, name) and not on its owner precisely because
  # it moves; a character's whereabouts is re-asserted for the same reason. The
  # file is the decision, so re-seeding puts a played world's cast back.
  test "re-seeding puts a character back where the file says" do
    story = WorldSeed::Loader.new(document).load!
    corbel = story.characters.find_by(fullname: "Corbel Ashe")
    corbel.move_to!(story.locations.find_by(name: "The Hallway"))

    WorldSeed::Loader.new(document).load!

    assert_equal "The Closet", corbel.reload.location.name
  end

  # The one mistake this key can make is otherwise silent: the character loads
  # standing nowhere and the room they were meant to be in is empty.
  test "a character placed in a room the file does not declare is refused" do
    misplaced = document
    misplaced["characters"].last["location"] = "The Boiler Room"

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(misplaced).load! }
    assert_match(/Corbel Ashe.*placed in "The Boiler Room"/, error.message)
  end

  # ------------------------------------------------------------------------
  # A WORLD THAT HURTS YOU FOR WALKING AROUND IT. Both columns on both tables
  # are the world's, so a file is the only thing that writes one -- which makes
  # the file the only place the mistakes can be made and this the place to name
  # them.

  test "a room's hazard loads onto the room" do
    hazardous = document
    hazardous["locations"].last.merge!("hazard" => "unlit", "hazard_die" => 6)

    WorldSeed::Loader.new(hazardous).load!

    room = Story.find_by(title: "A Seeded World").locations.find_by(name: "The Hallway")
    assert_equal "unlit", room.hazard
    assert_equal 6, room.hazard_die
  end

  # WRITTEN IN BOTH DIRECTIONS ON EVERY LOAD, which is `danger`'s rule one key
  # over and is here for its reason: a stale hazard the file no longer declares
  # would go on costing players hit points with no way to undo it from the file.
  test "re-seeding without the key takes a hazard back off" do
    hazardous = document
    hazardous["locations"].last.merge!("hazard" => "unlit", "hazard_die" => 6)
    WorldSeed::Loader.new(hazardous).load!

    WorldSeed::Loader.new(document).load!

    room = Story.find_by(title: "A Seeded World").locations.find_by(name: "The Hallway")
    assert_nil room.hazard
    assert_nil room.hazard_die
  end

  # THE ONE PIECE OF NEW SEED-FORMAT SHAPE THE WHOLE DESIGN NEEDS. `between:` is
  # an unordered pair, so `hazard_from:` is the only way a file can say which of
  # the two directions costs something -- and the loader puts it on that ONE row.
  test "a doorway's hazard lands on the one direction the file names" do
    hazardous = document
    hazardous["connections"].first.merge!("hazard" => "drop", "hazard_die" => 4,
                                          "hazard_from" => "The Office")

    WorldSeed::Loader.new(hazardous).load!

    story = Story.find_by(title: "A Seeded World")
    office = story.locations.find_by(name: "The Office")
    closet = story.locations.find_by(name: "The Closet")

    assert_equal "drop", LocationConnection.walked(office, closet).hazard
    assert_nil LocationConnection.walked(closet, office).hazard
    assert_includes closet.exits, office, "a one-way hazard is not a one-way exit"
  end

  test "re-seeding the other way round moves the hazard rather than adding a second" do
    hazardous = document
    hazardous["connections"].first.merge!("hazard" => "drop", "hazard_die" => 4,
                                          "hazard_from" => "The Office")
    WorldSeed::Loader.new(hazardous).load!

    turned = document
    turned["connections"].first.merge!("hazard" => "drop", "hazard_die" => 4,
                                        "hazard_from" => "The Closet")
    WorldSeed::Loader.new(turned).load!

    story = Story.find_by(title: "A Seeded World")
    office = story.locations.find_by(name: "The Office")
    closet = story.locations.find_by(name: "The Closet")

    assert_nil LocationConnection.walked(office, closet).hazard
    assert_equal "drop", LocationConnection.walked(closet, office).hazard
  end

  test "a room hazard the catalogue has no entry for is refused by name" do
    broken = document
    broken["locations"].last.merge!("hazard" => "haunted", "hazard_die" => 4)

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(broken).load! }
    assert_match(/The Hallway.*hazard: "haunted"/, error.message)
  end

  test "a doorway hazard the catalogue has no entry for is refused by name" do
    broken = document
    broken["connections"].first.merge!("hazard" => "flooded", "hazard_die" => 4,
                                        "hazard_from" => "The Office")

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(broken).load! }
    assert_match(/The Office <-> The Closet.*hazard: "flooded"/, error.message)
  end

  # HALF A HAZARD IS THE SILENT MISTAKE: the file looks as though it said
  # something and the room is simply not hazardous.
  test "a hazard with no die is refused by name" do
    broken = document
    broken["locations"].last["hazard"] = "unlit"

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(broken).load! }
    assert_match(/hazard_die: nil/, error.message)
  end

  test "a die the engine does not throw is refused" do
    broken = document
    broken["locations"].last.merge!("hazard" => "unlit", "hazard_die" => 7)

    assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(broken).load! }
  end

  test "a doorway hazard with no direction is refused" do
    broken = document
    broken["connections"].first.merge!("hazard" => "drop", "hazard_die" => 4)

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(broken).load! }
    assert_match(/no `hazard_from`/, error.message)
  end

  test "a hazard_from naming a room that is not one of the edge's own ends is refused" do
    broken = document
    broken["connections"].first.merge!("hazard" => "drop", "hazard_die" => 4,
                                        "hazard_from" => "The Hallway")

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(broken).load! }
    assert_match(/not one of its own/, error.message)
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
        },
        {
          "fullname" => "Corbel Ashe", "race" => "Ashfolk", "location" => "The Closet", "nickname" => "Corbel",
          "age" => 33, "sex" => "male", "is_protagonist" => false, "is_companion" => false,
          "backstory" => "Kept the records after the fire.", "personality" => "Watchful and unhurried.",
          "appearance" => "Soot at the cuff, whatever he is wearing.",
          "likes" => "A shelf in the right order", "dislikes" => "Being asked twice",
          "fears" => "A door with no inventory number"
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
