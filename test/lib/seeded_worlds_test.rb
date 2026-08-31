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

  # The reason the opening arrival is world data rather than something a
  # playthrough invents. `Scene::Generator.characters_present` reads the last
  # scene in a location that recorded anyone, so an opening arrival with a
  # hand-authored cast is what makes `Playthrough::Classifier` offer somebody to
  # talk to -- previously it answered with the protagonist alone in both worlds,
  # and the talk branch was unreachable in a seeded world.
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

    assert_no_difference [ "Story.count", "Universe.count", "Race.count", "Location.count", "LocationConnection.count", "Character.count", "Item.count", "Scene.count" ] do
      WorldSeed::Loader.load_all(io: nil)
    end
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
