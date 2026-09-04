require "test_helper"

# Loads the worlds that are actually checked into db/seeds/worlds, so drift
# between the seed data and the schema fails here rather than silently.
#
# This is deliberately the ONLY test that reads those files. Generator tests
# must keep exercising the generators against fake agents -- a seeded world is
# not a substitute for generating one.
class SeededWorldsTest < ActiveSupport::TestCase
  test "there are worlds to seed" do
    assert_operator WorldSeed.files.size, :>=, 2, "the point of this is a fresh clone having something to play"
  end

  test "every checked-in world loads" do
    stories = WorldSeed::Loader.load_all(io: nil)

    assert_equal WorldSeed.files.size, stories.size
    assert_equal stories.map(&:title).uniq, stories.map(&:title), "story titles are the natural key, so they have to be unique"
  end

  test "every checked-in world is playable" do
    WorldSeed::Loader.load_all(io: nil).each do |story|
      opening = story.opening_location

      assert opening.realized?, "#{story.title}: PlaythroughsController refuses a story whose first location is a stub"
      assert opening.exits.any?, "#{story.title}: the opening location has no way out"
      assert story.protagonist.present?, "#{story.title}: a playthrough needs a protagonist to point at"
      assert story.universe.races.any?, "#{story.title}: characters are assigned a race from the universe"

      story.locations.realized.each do |location|
        assert location.description.present?, "#{story.title}: #{location.name} is realized with no description"
        assert location.exits.any?, "#{story.title}: #{location.name} is realized with no way out"
      end

      story.locations.stubs.each do |location|
        assert location.teaser.present?, "#{story.title}: the stub #{location.name} has no teaser to show"
      end
    end
  end

  test "every connection exists in both directions" do
    WorldSeed::Loader.load_all(io: nil).each do |story|
      LocationConnection.where(location: story.locations).each do |connection|
        reverse = LocationConnection.find_by(location: connection.connected_location, connected_location: connection.location)

        assert reverse, "#{story.title}: #{connection.location.name} -> #{connection.connected_location.name} has no way back"
        assert_equal connection.distance, reverse.distance
        assert_equal connection.travel_method, reverse.travel_method
        assert_equal connection.time_to_travel, reverse.time_to_travel
      end
    end
  end

  # Captain-decided: the single-exit behaviour needs permanent coverage in real
  # data, and the two worlds should not exercise the same happy path. A stub
  # neighbour does not count -- a stub has no exits until somebody walks into
  # it, so the dead end has to be realized to exist at all.
  test "at least one seeded world contains a realized dead end" do
    dead_ends = WorldSeed::Loader.load_all(io: nil).flat_map do |story|
      story.locations.realized.select { |location| location.exits.count == 1 }
    end

    assert dead_ends.any?, "no seeded world has a realized location with exactly one exit"
    dead_end = dead_ends.first
    assert_equal 1, dead_end.exits.count
    assert dead_end.exits.first.exits.count > 1, "the way back out of #{dead_end.name} should lead somewhere with choices"
  end

  # A seeded world opens with a narrated arrival and no model call, which is the
  # whole point of carrying it in the file: the first screen a new player sees is
  # the one they should never be made to wait for.
  test "every checked-in world opens with a narrated arrival" do
    BaseAgent.stub(:new, -> { flunk "seeding a world asked a model something" }) do
      WorldSeed::Loader.load_all(io: nil).each do |story|
        scene = story.opening_scene

        assert scene.present?, "#{story.title}: no opening arrival, so the first thing a player reads is a room description"
        assert_equal story.opening_location, scene.location, "#{story.title}: the player reads the opening arrival standing in the opening location"
        assert scene.description.present?, "#{story.title}: the opening arrival has nothing to read"
        assert_equal story.start_time, scene.story_timestamp, "#{story.title}: the story opens at its own start_time"
        assert_nil scene.previous_scene, "#{story.title}: nothing happens before the story opens"
      end
    end
  end

  # THE STORY-TIME HAZARD. These files sit on disk for months. If seeding stamped
  # the visit, the first player to walk back into the opening room would be told
  # in fiction that they had been gone that long.
  test "seeding a world does not put anybody in its opening room" do
    WorldSeed::Loader.load_all(io: nil).each do |story|
      assert_nil story.opening_location.last_protagonist_visit,
                 "#{story.title}: seeding a world is not somebody standing in a room"
    end
  end

  # WHERE THE CAST STANDS, and it is `characters[].location` in the file --
  # `Character.present_in`, the closed set `talk` resolves against. It replaced
  # reading the last scene in a room that recorded anybody, which meant a room
  # nobody had walked into had nobody in it however central the person standing
  # there was.
  test "every checked-in world places its cast, or means not to" do
    WorldSeed::Loader.load_all(io: nil).each do |story|
      placed = story.characters.somewhere.to_a

      assert placed.any?, "#{story.title}: nobody in this world is anywhere, so `talk` can never resolve"
      placed.each do |character|
        assert_equal story, character.location.story, "#{story.title}: #{character.fullname} stands in another story"
        assert_not character.is_protagonist?,
                   "#{story.title}: the protagonist's position is the playthrough's, not the story's"
      end
    end
  end

  # EVERY CHECKED-IN WORLD IS HEALTHY, and this is the assertion that keeps it
  # that way. `The Unrecorded Hour` was "playable, 1 warning" for one reason:
  # Perrin Lasco is nowhere on purpose and nothing said so, so the doctor
  # reported the world working exactly as written. `absent: true` in the file
  # is what says it.
  test "every checked-in world is healthy, with nothing for the doctor to report" do
    WorldSeed::Loader.load_all(io: nil).each do |story|
      doctor = Story::Doctor.new(story)

      assert_predicate doctor, :healthy?, "#{story.title}: #{doctor.findings.map(&:message).join("; ")}"
    end
  end

  # NOWHERE ON PURPOSE, said out loud by the one world that means it. The
  # counterpart of the tide post below: that world's premise is a man who is
  # THERE, this one's is a man who is GONE, and both are now records.
  test "the removed character of The Unrecorded Hour is absent on purpose" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-unrecorded-hour.yml"))
    perrin = story.characters.find_by(fullname: "Perrin Lasco")

    assert_predicate perrin, :absent?
    story.locations.each do |location|
      assert_not_includes Character.present_in(location).map(&:fullname), "Perrin Lasco",
                          "#{location.name} offers somebody the world has removed"
    end
  end

  # The premise character is the reason this whole record exists: The Salt
  # Assizes is about a man chained to the tide post, and arriving there used to
  # record the protagonist alone.
  test "the premise character of the held-out world is at the post" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-salt-assizes.yml"))
    post = story.locations.find_by(name: "The Tide Post")

    assert_equal [ "Neb Halloran" ], Character.present_in(post).pluck(:fullname)
    assert_equal [ "Neb Halloran" ], Scene::Generator.characters_present(post).map(&:fullname) - [ story.protagonist.fullname ]
  end

  # The reason the opening arrival is world data rather than something a
  # playthrough invents: it is the prose a player reads first. Who is standing
  # in the opening room is now `characters[].location` rather than that cast, so
  # the two have to agree -- an arrival that introduces somebody the classifier
  # will not offer is the defect this record replaced, running the other way.
  test "every checked-in world has somebody to talk to on turn one" do
    WorldSeed::Loader.load_all(io: nil).each do |story|
      present = Scene::Generator.characters_present(story.opening_location)
      others = present - [ story.protagonist ]

      assert others.any?, "#{story.title}: nobody is standing in #{story.opening_location.name}, so the talk branch cannot be reached"
      assert_includes present, story.protagonist, "#{story.title}: the protagonist is the one arriving"
    end
  end

  test "seeding is idempotent" do
    WorldSeed::Loader.load_all(io: nil)

    assert_no_difference [ "Story.count", "Universe.count", "Race.count", "Location.count", "LocationConnection.count", "Character.count", "Item.count", "Scene.count", "WorldMechanic.count" ] do
      WorldSeed::Loader.load_all(io: nil)
    end
  end

  # --- worlds that move ----------------------------------------------------

  # A seeded mechanic has to be RUNNABLE in the world it was written into, not
  # merely well-formed. The loader checks the file; this checks the graph the
  # file produced.
  test "every seeded mechanic has something it can actually do" do
    WorldSeed::Loader.load_all(io: nil).each do |story|
      story.world_mechanics.each do |mechanic|
        next unless mechanic.kind == "shuffle_connections"

        edges = mechanic.operation.anchor_edges

        assert_operator edges.size, :>=, 2,
                        "#{story.title}: #{mechanic.name} has #{edges.size} edge(s) to shuffle, so nothing can move"
        assert edges.all? { |edge| edge.location.mobile? && !edge.connected_location.mobile? }
      end
    end
  end

  test "a seeded world has not run any of its nights yet" do
    WorldSeed::Loader.load_all(io: nil).each do |story|
      story.world_mechanics.each do |mechanic|
        assert_nil mechanic.last_run_at,
                   "#{story.title}: #{mechanic.name} was seeded as though nights nobody played had happened"
      end
      assert_empty story.world_events, "#{story.title}: seeding a world is not the world having already moved"
    end
  end

  # The Lunar Cartographer's universe has claimed since it was generated that
  # Nocturnis rearranges itself every night. This is that claim, in the records.
  test "the Lunar Cartographer's city moves, and moving it keeps the world whole" do
    story = WorldSeed::Loader.load_all(io: nil).detect { |candidate| candidate.title == "The Lunar Cartographer" }
    mechanic = story.world_mechanics.sole
    before = story.locations.order(:id).to_h { |location| [ location.name, location.exits.count ] }

    # Three story nights, with no wall-clock time passing and no model call.
    create(:scene, story: story, location: story.opening_location, previous_scene: story.opening_scene,
                   story_timestamp: story.start_time + 3.days)
    events = story.catch_up_world!

    assert_equal 3, events.size
    assert_equal Time.utc(2026, 9, 1), events.first.occurred_at
    assert_equal Time.utc(2026, 9, 3), events.last.occurred_at
    assert_equal before, story.locations.order(:id).to_h { |location| [ location.name, location.reload.exits.count ] },
                 "the shuffle repoints edges; it does not add or lose them"

    reached = Set.new([ story.opening_location.id ])
    frontier = [ story.opening_location ]
    while (location = frontier.pop)
      location.exits.each { |exit| frontier << exit if reached.add?(exit.id) }
    end
    assert_equal story.locations.count, reached.size, "three nights of shuffling stranded part of the city"
  end

  # THE BUILDING HOLDS TOGETHER. Grenn laid his foundation stones loose so it
  # would; in the data, that is every room of it being `mobile`, which makes the
  # doors between them edges the shuffle never touches.
  test "the boarding house keeps its own doors when the quarter travels" do
    story = WorldSeed::Loader.load_all(io: nil).detect { |candidate| candidate.title == "The Lunar Cartographer" }
    room = story.opening_location
    before = room.exits.order(:id).pluck(:name)

    create(:scene, story: story, location: room, previous_scene: story.opening_scene,
                   story_timestamp: story.start_time + 5.days)
    story.catch_up_world!

    assert_equal before, room.reload.exits.order(:id).pluck(:name)
  end

  test "the other seeded world stays where it is" do
    story = WorldSeed::Loader.load_all(io: nil).detect { |candidate| candidate.title != "The Lunar Cartographer" }

    assert_empty story.world_mechanics, "a world does not have to move; `mechanics` is optional"
    assert_empty story.locations.mobile
  end

  # The checked-in files are hand-edited, so they have to survive the tooling:
  # loading one and exporting it again must produce the file on disk.
  test "every checked-in world round-trips through the exporter" do
    WorldSeed.files.each do |path|
      story = WorldSeed::Loader.load_file(path)
      exported = WorldSeed.dump(WorldSeed::Exporter.new(story).document)
      on_disk = File.read(path)

      assert_equal WorldSeed.parse(on_disk), WorldSeed.parse(exported),
                   "#{File.basename(path)} does not survive a load-and-export round trip"
    end
  end
end
