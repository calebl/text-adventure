require "test_helper"

# THE SWEEP ITSELF, RUN IN CI. `rake game:sweep` is the console front end; this
# is the same call from the suite, so every stored script is walked on every
# `bin/rails test` and a green build means the engine still does what the
# scripts say it does.
#
# IT COSTS NOTHING TO RUN HERE, which is the whole reason it can live in the
# suite: no model, no network, no key, and each script loads its own copy of a
# seeded world inside a transaction that is rolled back. See `EngineSweep`.
#
# THE FAILURE MESSAGE IS THE FEATURE. Whoever reads it has a CI log and nothing
# else, so it names the script, the step, what was typed and both sides of the
# expectation that did not hold -- `EngineSweep::Result::Failure` builds it and
# `test/lib/engine_sweep_test.rb` is where that is proved rather than hoped for.
class EngineSweepTest < ActiveSupport::TestCase
  test "every stored script walks the engine and the records say what it says" do
    results = EngineSweep.run

    assert_predicate results, :any?, "there are no sweep scripts in #{EngineSweep::DIRECTORY}"
    assert results.all?(&:passed?), <<~FAILED
      The engine sweep failed. Each finding below names the script, the step, the line
      that was typed, and what the records said instead:

      #{results.reject(&:passed?).map(&:report).join("\n\n")}
    FAILED
  end

  test "the scripts between them walk every seeded world" do
    walked = EngineSweep.scripts.map(&:story).uniq

    assert_equal Eval::STORIES.sort, walked.sort,
                 "a seeded world with no sweep script is a world nothing walks offline"
  end

  # THE GUARD, asserted rather than assumed. `BaseAgent.new` is the one gate
  # every model call in this app goes through, so a sweep that got past it would
  # be spending money in CI.
  test "a model call from inside a sweep fails the sweep" do
    error = assert_raises(EngineSweep::ModelCalled) do
      EngineSweep.without_a_model { BaseAgent.new(purpose: "classifier") }
    end

    assert_match(/classifier/, error.message)
  end

  # And the class is handed back intact, including when the sweep raised. A
  # poisoned `BaseAgent` would fail every test that ran after this one, in an
  # order that depends on which worker they landed in.
  test "the guard is lifted again even when a walk raises" do
    assert_raises(RuntimeError) { EngineSweep.without_a_model { raise "a walk went wrong" } }

    agent = BaseAgent.new(purpose: "classifier")

    assert_instance_of BaseAgent, agent
  end

  # A sweep leaves nothing behind. It loads its own copy of the world under a
  # title of its own and rolls the whole walk back, so running it against a
  # database somebody is playing in changes neither.
  test "a walk keeps nothing, including the copy of the world it walked" do
    story = create(:story, title: "The Unrecorded Hour")

    assert_no_difference [ "Story.count", "Location.count", "Item.count", "Playthrough.count", "LocationConnection.count" ] do
      EngineSweep.run(EngineSweep.scripts.select { |script| script.story == "The Unrecorded Hour" })
    end

    assert_equal "The Unrecorded Hour", story.reload.title
    assert_nil Story.find_by(title: "The Unrecorded Hour#{EngineSweep::Walk::TITLE_SUFFIX}")
  end

  # --- the script format -----------------------------------------------------

  test "an expectation that does not hold is reported with the script, the step, the line and both sides" do
    result = walk(<<~SCRIPT)
      story: The Unrecorded Hour
      steps:
      - id: the-wrong-room
        type: go to the Supply Closet
        why: a deliberately wrong expectation
        expect:
          location: The Long Hallway
    SCRIPT

    assert_not_predicate result, :passed?
    failure = result.failures.sole.to_s

    assert_match(/step 1 the-wrong-room/, failure)
    assert_match(/typed "go to the Supply Closet"/, failure)
    assert_match(/expected location: The Long Hallway/, failure)
    assert_match(/the records say:\s+The Supply Closet/, failure)
    # The engine's own read-out comes with it: the next question is always what
    # the room looked like.
    assert_match(/lying here\s+Perrin's private index/, failure)
  end

  test "a misspelt expectation raises rather than passing quietly" do
    error = assert_raises(EngineSweep::InvalidScript) do
      walk(<<~SCRIPT)
        story: The Unrecorded Hour
        steps:
        - type: look
          expect:
            carying: []
      SCRIPT
    end

    assert_match(/carying/, error.message)
    assert_match(/carrying/, error.message)
  end

  test "a misspelt step key raises too, so a second player cannot be silently ignored" do
    error = assert_raises(EngineSweep::InvalidScript) do
      walk(<<~SCRIPT)
        story: The Unrecorded Hour
        steps:
        - type: look
          plyer: second
      SCRIPT
    end

    assert_match(/plyer/, error.message)
  end

  # --- re-seeding a world the walk is in the middle of playing ---------------
  #
  # `reseed:` is the second thing a step can be that is not a line somebody
  # typed, and it is here because a re-seed is what the captain does daily and
  # nothing walked it. See `EngineSweep::Script`'s header.

  # A re-seed re-asserts the file over THE WORLD LAYER and reaches no game at
  # all, so the stamp this player picked up stays in their hands and the room's
  # own doorways are unchanged. It used to be asserted the other way round --
  # `here: [ward stamp]`, `carrying: [daybook]` -- because before the captain's
  # ruling of 2026-09-04 there was one row and putting the file's item back
  # necessarily took it off whoever had it.
  test "a re-seed step puts back what the file says and creates nothing" do
    result = walk(<<~SCRIPT)
      story: The Unrecorded Hour
      steps:
      - type: take the ward stamp
        expect:
          carrying: [Ward Office 12 daybook, ward stamp]
      - reseed: true
        expect:
          changed: false
          here: []
          carrying: [Ward Office 12 daybook, ward stamp]
          exits: [The Supply Closet (realized), The Long Hallway (stub)]
    SCRIPT

    assert_predicate result, :passed?, result.report
  end

  # AND THE WORLD'S OWN ROW REALLY DID GO BACK, which the walk above cannot show
  # from inside one game: the party's floor is empty either way, because their
  # copy is in their hands. A second player who never touched anything reads it.
  test "a re-seed puts the world's own row back, and a second game reads it" do
    result = walk(<<~SCRIPT)
      story: The Unrecorded Hour
      steps:
      - type: take the ward stamp
        expect:
          carrying: [Ward Office 12 daybook, ward stamp]
      - reseed: true
        expect:
          here: []
      - type: look
        player: second
        expect:
          here: [ward stamp]
          carrying: [Ward Office 12 daybook]
    SCRIPT

    assert_predicate result, :passed?, result.report
  end

  # THE DEFECT: before `WorldSeed.natural_key`, a room the file renamed was a
  # room that did not exist yet, so this load created a second closet and the
  # office opened onto both.
  test "a re-seed that renames a room renames the row rather than adding one" do
    result = walk(<<~SCRIPT)
      story: The Unrecorded Hour
      steps:
      - reseed:
          locations: { The Supply Closet: Supply Closet }
        expect:
          exits: [Supply Closet (realized), The Long Hallway (stub)]
          note: 'is "Supply Closet" in the file, so the row was renamed'
    SCRIPT

    assert_predicate result, :passed?, result.report
  end

  test "a step that is both a typed line and a re-seed raises" do
    error = assert_raises(EngineSweep::InvalidScript) do
      walk(<<~SCRIPT)
        story: The Unrecorded Hour
        steps:
        - type: look
          reseed: true
      SCRIPT
    end

    assert_match(/can only be one/, error.message)
  end

  test "a misspelt reseed rename key raises rather than reading as a plain re-seed" do
    error = assert_raises(EngineSweep::InvalidScript) do
      walk(<<~SCRIPT)
        story: The Unrecorded Hour
        steps:
        - reseed:
            location: { The Supply Closet: Supply Closet }
      SCRIPT
    end

    assert_match(/location/, error.message)
    assert_match(/locations/, error.message)
  end

  # --- two people playing one world -----------------------------------------
  #
  # THE ONE THING A SINGLE WALK CANNOT SEE. With the inventory on the story's
  # protagonist row both playthroughs read the same hands, so no one-player
  # script could tell a story-level inventory from a playthrough-level one.

  test "a second player is a second playthrough of the same loaded world" do
    result = walk(<<~SCRIPT)
      story: The Unrecorded Hour
      steps:
      - type: take the ward stamp
        expect:
          changed: true
          carrying: [Ward Office 12 daybook, ward stamp]
      - type: inventory
        player: second
        expect:
          carrying: [Ward Office 12 daybook]
      - type: look
        expect:
          carrying: [Ward Office 12 daybook, ward stamp]
    SCRIPT

    assert_predicate result, :passed?, result.report
  end

  test "a step with no player goes to the same one game as every other" do
    assert_equal [ EngineSweep::Script::DEFAULT_PLAYER ],
                 script(<<~SCRIPT).players
                   story: The Unrecorded Hour
                   steps:
                   - type: look
                   - type: inventory
                 SCRIPT
  end

  test "a failure names which player typed the line" do
    result = walk(<<~SCRIPT)
      story: The Unrecorded Hour
      steps:
      - type: look
        player: second
        expect:
          carrying: []
    SCRIPT

    assert_not_predicate result, :passed?
    assert_match(/\(second\)/, result.failures.sole.to_s)
  end

  test "a script naming a world that is not seeded says so" do
    error = assert_raises(EngineSweep::InvalidScript) do
      walk("story: A World Nobody Wrote\nsteps:\n- type: look\n")
    end

    assert_match(/A World Nobody Wrote/, error.message)
  end

  test "an exit expectation reads the detail level as well as the name" do
    result = walk(<<~SCRIPT)
      story: The Unrecorded Hour
      steps:
      - type: look
        expect:
          exits: [The Supply Closet (stub), The Long Hallway (stub)]
    SCRIPT

    assert_not_predicate result, :passed?
    assert_match(/expected exits: The Supply Closet \(stub\)/, result.failures.sole.to_s)
  end

  # --- the invariants, which no typed line can break ------------------------

  # AN INVENTED DOOR is something `Location::Generator` writes, not something a
  # player types, so it is checked here against the records directly. That is
  # the whole reason `EngineSweep::Invariants` exists as a check over the world
  # rather than as an expectation on a step.
  test "a door the world file does not have is caught after the walk" do
    seed, story = seeded_copy("the-unrecorded-hour")
    closet, hallway = story.locations.where(name: [ "The Supply Closet", "The Long Hallway" ]).order(:id).to_a
    connect(closet, hallway)

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "doors_unchanged", broken.invariant
    assert_match(/The Long Hallway <-> The Supply Closet/, broken.to_s)
  end

  test "a room over the exit cap is caught after the walk" do
    seed, story = seeded_copy("the-unrecorded-hour")
    office = story.locations.find_by(name: "Ward Office 12")
    (Location::ExitsSchema::MAX_EXITS + 1).times do |number|
      connect(office, create(:location, :stub, story: story, name: "Corridor #{number}"))
    end

    caught = EngineSweep::Invariants.new(story, seed: seed).check.map(&:invariant)

    assert_includes caught, "exit_cap"
  end

  test "an item that ended the walk in no place at all is caught after the walk" do
    seed, story = seeded_copy("the-unrecorded-hour")
    # Straight to the column, because the model refuses to save it this way --
    # which is the point: this invariant is about a row that got past the app.
    Item.where(location: story.locations).find_by(name: "ward stamp")
        .update_columns(character_id: nil, location_id: nil)

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "items_accounted", broken.invariant
    assert_match(/ward stamp/, broken.to_s)
  end

  # NOTHING A PLAYER TYPES MAY MOVE ANYBODY. The seed file, `Character::Registry`
  # at realization (which this mode cannot reach) and an explicit
  # `Character#move_to!` are the only writers of a whereabouts, so a walk that
  # moved somebody means a typed line has started moving people.
  test "somebody who moved during an offline walk is caught after it" do
    seed, story = seeded_copy("the-unrecorded-hour")
    story.characters.find_by(fullname: "Halkett Rowe")
         .move_to!(story.locations.find_by(name: "The Supply Closet"))

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "cast_unmoved", broken.invariant
    assert_match(/Halkett Rowe is in The Supply Closet and the file says in Ward Office 12/, broken.to_s)
  end

  test "somebody who lost their room during an offline walk is caught too" do
    seed, story = seeded_copy("the-unrecorded-hour")
    story.characters.find_by(fullname: "Halkett Rowe").move_to!(nil)

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "cast_unmoved", broken.invariant
    assert_match(/is nowhere and the file says in Ward Office 12/, broken.to_s)
  end

  # NOWHERE IS A LEGITIMATE STATE and the invariant is stated as "unmoved"
  # rather than "nobody is nowhere" for exactly this: the protagonist carries no
  # whereabouts at all, and Perrin Lasco is nowhere because that world means it.
  test "the people the file leaves nowhere are not a broken invariant" do
    seed, story = seeded_copy("the-unrecorded-hour")

    assert_predicate story.characters.find_by(fullname: "Perrin Lasco"), :nowhere?
    assert_predicate story.protagonist, :nowhere?
    assert_empty EngineSweep::Invariants.new(story, seed: seed).check
  end

  # `present` is the closed set `talk` resolves against, read back with no
  # model -- which is what it took to make presence sweepable at all.
  test "a present expectation reads who the records place in the room" do
    result = walk(<<~YAML)
      story: The Salt Assizes
      steps:
      - type: look
        expect:
          present: [Ammon Brace]
      - type: go to the Tide Post
        expect:
          present: [Neb Halloran]
    YAML

    assert_predicate result, :passed?, result.report
  end

  test "a present expectation that does not hold names both sides" do
    result = walk(<<~YAML)
      story: The Salt Assizes
      steps:
      - type: look
        expect:
          present: [Neb Halloran]
    YAML

    assert_not result.passed?
    assert_match(/expected present: Neb Halloran/, result.report)
    assert_match(/the records say:      Ammon Brace/, result.report)
  end

  test "a room that got written during an offline walk is caught after it" do
    seed, story = seeded_copy("the-unrecorded-hour")
    story.locations.find_by(name: "The Long Hallway")
         .update!(detail_level: "realized", description: "A hallway.", lore: "Somebody wrote it.")

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "nothing_was_written", broken.invariant
  end

  private

  # One script written inline, played the way the rake task plays the stored
  # ones. Written to a file because a script IS a file -- there is no second way
  # to build one, so there is no second thing for this test to be testing.
  def walk(yaml)
    EngineSweep.run([ script(yaml) ]).sole
  end

  # A script parsed from a string, written to a real file because `Script.load`
  # reports every failure by path and a fixture with no path reads as a bug in
  # the sweep.
  def script(yaml)
    file = Rails.root.join("tmp", "engine_sweep_test_#{SecureRandom.hex(4)}.yml")
    file.write(yaml)

    EngineSweep::Script.load(file)
  ensure
    file&.delete if file&.exist?
  end

  # A seeded world loaded the way a walk loads it -- under its own title, so
  # nothing here touches a world anybody is playing -- with the file it came
  # from, which is what the invariants compare against.
  def seeded_copy(slug)
    seed = WorldSeed.parse(File.read(WorldSeed::DIRECTORY.join("#{slug}.yml")))
    document = seed.deep_dup
    document["story"]["title"] = "#{seed["story"]["title"]}#{EngineSweep::Walk::TITLE_SUFFIX}"

    [ seed, WorldSeed::Loader.new(document).load! ]
  end

  def connect(from, to)
    [ [ from, to ], [ to, from ] ].each do |origin, destination|
      create(:location_connection, location: origin, connected_location: destination,
                                   distance: "adjacent", travel_method: "walking")
    end
  end
end
