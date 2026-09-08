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
  # THE ORDERED ROUTE THROUGH THE ONE ARC IN THE REPOSITORY, to the turn it
  # closes on. Shared by the `ending_words:` walks below, whose LAST step is the
  # one being asserted -- the route itself is `an-ending-with-words.yml`'s and is
  # not what those tests are about.
  TO_THE_END = [ "take the signet ring", "go to the obsidian maw", "go to Blackfang Tunnel",
                 "go to Blackfang Warren room 1", "go to Blackfang Warren room 2",
                 "go to the dry cell" ].freeze

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

    assert_empty Eval::STORIES - walked,
                 "a seeded world with no sweep script is a world nothing walks offline"
  end

  # AND EVERY WORLD A SCRIPT NAMES IS A WORLD SOMEBODY CHECKED IN, one way or
  # the other. A script may walk a world of the sweep's own (`EngineSweep::WORLDS`)
  # -- The Quay House is one, because a laid-out interior is not something any
  # world a person plays has -- and a title that is neither is a typo that would
  # otherwise fail as "there is no seeded world", one script at a time.
  test "every world a script names is checked in somewhere" do
    missing = EngineSweep.scripts.reject { |script| File.exist?(script.seed_file) }

    assert_empty missing.map(&:name),
                 "#{missing.map { |script| "#{script.name} wants #{script.seed_file}" }.join("; ")}"
  end

  # A SWEEP WORLD IS A WORLD IN EVERY OTHER RESPECT: the same format, the same
  # loader, the same validations. One that could not be loaded and played would
  # be a fixture pretending to be a world -- see `EngineSweep::WORLDS`.
  test "a world of the sweep's own loads and is healthy" do
    Dir.glob(EngineSweep::WORLDS.join("*.yml")).sort.each do |path|
      story = WorldSeed::Loader.new(WorldSeed.parse(File.read(path)), source: path).load!

      assert_predicate Story::Doctor.new(story), :healthy?,
                       "#{File.basename(path)}: #{Story::Doctor.new(story).findings.map(&:message).join("; ")}"
    end
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

  # `storey:` READS THE ROOM'S OWN BOX and nothing printed. Walked over The Quay
  # House because it is the only world with an interior at all, and asserted in
  # both polarities: the number that holds, and the number that does not.
  test "a storey expectation is read off the room's box, and an unmet one is reported" do
    passing = walk(<<~SCRIPT)
      story: The Quay House
      steps:
      - id: down-into-the-cellar
        type: go to The Bonded Cellar room 1
        why: the entry room of the one place in the repository that descends
        expect:
          storey: 0
      - id: and-on-down
        type: go to The Bonded Cellar room 2
        why: across the ground floor to where the stairs down land
        expect:
          storey: 0
      - id: below-the-way-in
        type: go to The Bonded Cellar room 5
        why: a storey below the entry
        expect:
          storey: -1
    SCRIPT

    assert_predicate passing, :passed?, passing.failures.map(&:to_s).join("\n")

    failing = walk(<<~SCRIPT)
      story: The Quay House
      steps:
      - id: the-wrong-storey
        type: go to The Bonded Cellar room 1
        why: a deliberately wrong storey
        expect:
          storey: -1
    SCRIPT

    assert_not_predicate failing, :passed?
    assert_match(/expected storey: -1/, failing.failures.sole.to_s)
    assert_match(/the records say:\s+0/, failing.failures.sole.to_s)
  end

  # THE ENDING'S OWN WORDS, and the two ways a script can be wrong about them.
  # The passing walk is checked in as `an-ending-with-words.yml` -- run by the
  # first test in this file -- so what is left to pin here is that the key
  # FAILS: a wrong sentence and an `[]` after the game ended both have to be
  # unmet, or the assertion the whole fallback rests on could pass on a game
  # with nothing to read.
  test "an ending_words expectation is read off the closing scene and an unmet one is reported" do
    wrong_words = walk(to_the_end("ending" => "rescued",
                                   "ending_words" => [ "the prince was never there at all" ]))

    assert_not_predicate wrong_words, :passed?
    assert_match(/expected ending_words/, wrong_words.failures.sole.to_s)
    assert_match(/The prince is found alive/, wrong_words.failures.sole.to_s,
                 "the failure prints the words the game really ended with")

    claiming_nothing = walk(to_the_end("ending" => "rescued", "ending_words" => []))

    assert_not_predicate claiming_nothing, :passed?
    assert_match(/no last paragraph yet/, claiming_nothing.failures.sole.to_s)
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
          here: [filing press]
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
          here: [filing press]
      - type: look
        player: second
        expect:
          here: [ward stamp, filing press]
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

  # NO TWO ROOMS OF ONE PLACE ANSWER TO ONE NAME. Nothing offline writes a room
  # name -- `Location::RoomName` does it at realization and a sweep has no model
  # -- so this holds on every walk today and fires the moment one starts
  # renaming rooms. `doors_unchanged`'s own argument, applied to names.
  #
  # THE OTHER BROKEN INVARIANTS ARE EXPECTED HERE: the three checked-in worlds
  # declare no boxes, so a room built with one is `geometry_unmoved`'s business
  # as well. The assertion is on the one being tested.
  test "two rooms of one place answering to one name are caught after the walk" do
    seed, story = seeded_copy("the-unrecorded-hour")
    broken = room_names_checked(seed, story, [ "the counting room", "the counting room" ])

    assert_not_nil broken
    assert_match(/The Custom House has 2 rooms called "the counting room"/, broken.to_s)
  end

  # AND ONE NAME WRITTEN TWO WAYS IS STILL ONE NAME, on `WorldSeed.natural_key`
  # -- the reading `Story::Doctor#duplicate_locations` reports a duplicate on
  # and the one `Location::RoomName` refuses a proposal on.
  test "one room name written two ways is one name to this invariant" do
    seed, story = seeded_copy("the-unrecorded-hour")

    assert_not_nil room_names_checked(seed, story, [ "The Counting Room", "counting room" ])
  end

  test "two rooms of one place with names of their own are not a broken invariant" do
    seed, story = seeded_copy("the-unrecorded-hour")

    assert_nil room_names_checked(seed, story, [ "the counting room", "the cold store" ])
  end

  # ROOMS OF A PLACE AND NOT EVERY CHILD ROW. Plain containment -- a district a
  # street sits in -- is ordinary places, and their duplicates are
  # `Story::Doctor#duplicate_locations`' over the whole story.
  test "two streets of one district sharing a name are not this invariant's" do
    seed, story = seeded_copy("the-unrecorded-hour")
    district = create(:location, :stub, story: story, name: "The Docks District")
    2.times { create(:location, :stub, story: story, name: "Warehouse Row", parent_location: district) }

    caught = EngineSweep::Invariants.new(story, seed: seed).check.map(&:invariant)

    assert_not_includes caught, "room_names_unique"
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

  # --- a fight, asserted without asserting a die ------------------------------
  #
  # `Roll`'s seed is built out of ROW IDS (`Roll.seed`), so what a blow COST is
  # not reproducible between the captain's database and a fresh one, and what a
  # turn DID is. `blows:` is the second, and it is the whole of how a script
  # walks a fight. Same line `a-check-against-an-ability.yml` draws for the d20.

  test "a blows expectation counts the rows a line wrote" do
    result = walk(<<~YAML)
      story: The Lunar Cartographer
      steps:
      - type: go to the hallway
        expect:
          blows: 0
      - type: go to The Bell of Saint Aravel
        expect:
          # Arriving is free: the riposte runs in the room the turn BEGAN in.
          blows: 0
          foes: [Marek Sollen]
      - type: /attack Marek Sollen
        expect:
          # The player's own, and the one live foe's answer, in one round.
          blows: 2
    YAML

    assert_predicate result, :passed?, result.report
  end

  test "a refused line writes no blow, and the expectation says so" do
    result = walk(<<~YAML)
      story: The Lunar Cartographer
      steps:
      - type: go to the hallway
      - type: go to The Bell of Saint Aravel
      - type: /attack Marek Sollen
      - type: take the rope
        expect:
          refused: true
          blows: 0
    YAML

    assert_predicate result, :passed?, result.report
  end

  test "an hp_of expectation reads a person's hit points off the records" do
    result = walk(<<~YAML)
      story: The Lunar Cartographer
      steps:
      - type: go to the hallway
      - type: go to The Bell of Saint Aravel
        expect:
          hp_of:
            Marek Sollen: 10
    YAML

    assert_predicate result, :passed?, result.report
  end

  test "an hp_of for somebody who is not standing here is unmet rather than skipped" do
    result = walk(<<~YAML)
      story: The Lunar Cartographer
      steps:
      - type: look
        expect:
          hp_of:
            Marek Sollen: 10
    YAML

    assert_not result.passed?
    assert_match(/Marek Sollen is not standing here/, result.report)
  end

  test "an hp_of that is not a mapping of names to whole numbers raises" do
    error = assert_raises(EngineSweep::InvalidScript) do
      walk(<<~YAML)
        story: The Unrecorded Hour
        steps:
        - type: look
          expect:
            hp_of: [Halkett Rowe]
      YAML
    end

    assert_match(/hp_of/, error.message)
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

  # --- a world that contains an enemy ----------------------------------------
  #
  # HOSTILITY IS THE WORLD'S, on exactly the terms a hit die is. The seed file,
  # the derivation at creation and the roll a room is born with are the writers;
  # no typed line is on that list, and `hostility_unmoved` is the assertion.

  test "a foes expectation reads who in this room means the party harm" do
    result = walk(<<~YAML)
      story: The Lunar Cartographer
      steps:
      - type: look
        expect:
          present: [Grenn Ollivar]
          foes: []
      - type: go to the hallway
        expect:
          foes: []
      - type: go to The Bell of Saint Aravel
        expect:
          present: [Marek Sollen]
          foes: [Marek Sollen]
    YAML

    assert_predicate result, :passed?, result.report
  end

  test "a foes expectation that does not hold names both sides" do
    result = walk(<<~YAML)
      story: The Lunar Cartographer
      steps:
      - type: look
        expect:
          foes: [Grenn Ollivar]
    YAML

    assert_not result.passed?
    assert_match(/expected foes: Grenn Ollivar/, result.report)
    assert_match(/the records say:\s+nothing/, result.report)
  end

  test "somebody who became hostile during an offline walk is caught after it" do
    seed, story = seeded_copy("the-unrecorded-hour")
    story.characters.find_by(fullname: "Halkett Rowe").update!(hostile: true)

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "hostility_unmoved", broken.invariant
    assert_match(/Halkett Rowe is hostile and the file says not hostile/, broken.to_s)
  end

  test "a foe the file arms who was disarmed during a walk is caught too" do
    seed, story = seeded_copy("the-lunar-cartographer")
    story.characters.find_by(fullname: "Marek Sollen").update!(hostile: false)

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "hostility_unmoved", broken.invariant
    assert_match(/Marek Sollen is not hostile and the file says hostile/, broken.to_s)
  end

  test "a race that changed sides during an offline walk is caught after it" do
    seed, story = seeded_copy("the-unrecorded-hour")
    story.universe.races.find_by(name: "Marginalia").update!(monstrous: true)

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "hostility_unmoved", broken.invariant
    assert_match(/"Marginalia" is monstrous and the file says a people/, broken.to_s)
  end

  test "a room that became dangerous during an offline walk is caught after it" do
    seed, story = seeded_copy("the-unrecorded-hour")
    story.locations.find_by(name: "The Supply Closet").update!(danger: "deadly")

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "hostility_unmoved", broken.invariant
    assert_match(/The Supply Closet is deadly and the file says safe/, broken.to_s)
  end

  # --- a world that hurts you for walking around it -------------------------
  #
  # A HAZARD IS THE WORLD'S, on exactly the terms hostility and a hit die are:
  # a seed file writes it and no typed line may. `hazards_unmoved` is its own
  # check rather than three more lines under `hostility_unmoved`, because one of
  # the two columns is not on a `Location` at all and an invariant reporting a
  # moved DOORWAY under the heading "hostility" would send a reader to the wrong
  # table.

  test "a hazards expectation counts what the place took and never what a foe took" do
    result = walk(<<~YAML)
      story: The Salt Assizes
      steps:
      - type: look
        expect:
          hazards: 0
          blows: 0
      - type: go to the Vestry Hulk
        expect:
          hazards: 1
          blows: 0
      - type: go to the Causeway Court
        expect:
          hazards: 0
    YAML

    assert_predicate result, :passed?, result.report
  end

  test "a hazards expectation that does not hold names both sides" do
    result = walk(<<~YAML)
      story: The Salt Assizes
      steps:
      - type: look
        expect:
          hazards: 2
    YAML

    assert_not result.passed?
    assert_match(/expected hazards: 2/, result.report)
  end

  test "a room that became hazardous during an offline walk is caught after it" do
    seed, story = seeded_copy("the-unrecorded-hour")
    story.locations.find_by(name: "The Supply Closet").update!(hazard: "airless", hazard_die: 4)

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "hazards_unmoved", broken.invariant
    assert_match(/The Supply Closet has hazard "airless" and the file says nil/, broken.to_s)
  end

  test "a hazard the file wrote that a walk took off is caught too" do
    seed, story = seeded_copy("the-salt-assizes")
    story.locations.find_by(name: "The Tide Post").update!(hazard: nil, hazard_die: nil)

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "hazards_unmoved", broken.invariant
    assert_match(/The Tide Post has hazard nil and the file says "flooded"/, broken.to_s)
  end

  # THE DIRECTED HALF: the file's answer is about ONE of the two rows, so a
  # hazard that turned round during a walk is two complaints -- the row that
  # lost it and the row that gained it.
  test "a doorway hazard that turned round during a walk is caught after it" do
    seed, story = seeded_copy("the-salt-assizes")
    court = story.locations.find_by(name: "The Causeway Court")
    hulk = story.locations.find_by(name: "The Vestry Hulk")
    LocationConnection.walked(court, hulk).update!(hazard: nil, hazard_die: nil)
    LocationConnection.walked(hulk, court).update!(hazard: "drop", hazard_die: 4)

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "hazards_unmoved", broken.invariant
    assert_match(/from The Causeway Court into The Vestry Hulk has hazard nil/, broken.to_s)
    assert_match(/from The Vestry Hulk into The Causeway Court has hazard "drop"/, broken.to_s)
  end

  # A WORLD THAT MEANS IT IS NOT A BROKEN INVARIANT: the Salt Assizes really is
  # hazardous and walking it must not read as a defect.
  test "the world the file makes hazardous is not a broken invariant" do
    seed, story = seeded_copy("the-salt-assizes")

    assert_equal "flooded", story.locations.find_by(name: "The Tide Post").hazard
    assert_equal [], EngineSweep::Invariants.new(story, seed: seed).check
  end

  # A WORLD THAT MEANS IT IS NOT A BROKEN INVARIANT, which is why this is stated
  # as "unmoved" against the file rather than as "no world has monsters".
  test "the world the file arms is not a broken invariant" do
    seed, story = seeded_copy("the-lunar-cartographer")

    assert_predicate story.characters.find_by(fullname: "Marek Sollen"), :hostile?
    assert_predicate story.universe.races.find_by(name: "Nocturna-Blighted"), :monstrous?
    assert_equal "dangerous", story.locations.find_by(name: "The Bell of Saint Aravel").danger
    assert_empty EngineSweep::Invariants.new(story, seed: seed).check
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
  # The route above as a script, with `expect` on its last step only. Built as a
  # document rather than as a heredoc because the steps are a list this file
  # holds, and interpolating six lines into a heredoc is an indentation bug
  # waiting to happen.
  def to_the_end(expectations)
    steps = TO_THE_END.map { |line| { "type" => line } }
    steps.last["expect"] = expectations

    { "story" => "The Iron Gate Descends", "steps" => steps }.to_yaml
  end

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

  # --- the shape of a place, which no typed line may touch -------------------
  #
  # THE STANDING CONSTRAINT APPLIED TO GEOMETRY. A box is the WORLD's on exactly
  # the terms a hit die and a hazard already are: the engine owns every one of
  # those numbers, and no model and no player prose writes one. Nothing in the
  # play path so much as reads a coordinate today, which is precisely why the
  # invariant is worth having now -- it fires the moment anything in a walk
  # starts writing one, which is the change that would need watching.

  # THE THREE CHECKED-IN WORLDS ARE FLAT (the captain's fourth ruling of
  # 2026-09-06), so a real walk over one of them has to leave this quiet. This
  # is the assertion that the invariant does not fire on the ordinary world.
  test "a walk over a seeded world leaves its geometry unmoved" do
    result = walk(<<~YAML)
      story: The Unrecorded Hour
      steps:
      - type: look
      - type: go to The Supply Closet
      - type: go to Ward Office 12
    YAML

    assert_predicate result, :passed?, result.report
  end

  test "a room that acquired a box during an offline walk is caught after it" do
    seed, story = seeded_copy("the-unrecorded-hour")
    place = story.locations.find_by(name: "Ward Office 12")
    place.update!(width: 12, depth: 8)

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "geometry_unmoved", broken.invariant
    assert_match(/Ward Office 12 is 12x8 paces inside nothing and the file says unlaid out/, broken.to_s)
  end

  # BOTH WAYS, like `#danger_of_the_rooms`: a room that LOST its box during a
  # walk fails exactly as loudly as one that gained one.
  test "a room that lost the box the file gives it is caught too" do
    seed, story = seeded_copy("the-unrecorded-hour")
    seed["locations"].detect { |row| row["name"] == "The Supply Closet" }.merge!("width" => 3, "depth" => 2)

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "geometry_unmoved", broken.invariant
    assert_match(/The Supply Closet is unlaid out/, broken.to_s)
  end

  # SIX FACTS PER ROOM AND NOT FIVE. The parent is the frame every one of the
  # five numbers is read in, so a walk that re-parented a room would move it
  # without changing a single number -- and an invariant over the columns alone
  # would not notice.
  test "a room that was re-parented during a walk is caught even with its numbers untouched" do
    seed, story = seeded_copy("the-unrecorded-hour")
    closet, hallway = story.locations.where(name: [ "The Supply Closet", "The Long Hallway" ]).order(:id).to_a
    closet.update!(parent_location: hallway)

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "geometry_unmoved", broken.invariant
    assert_match(/inside The Long Hallway and the file says unlaid out, inside nothing/, broken.to_s)
  end

  # A WORLD THAT DOES HAVE AN INTERIOR still has to walk clean, or the invariant
  # would only ever hold on worlds with no geometry to move.
  test "a world with an interior the file declares walks with the invariant quiet" do
    seed = WorldSeed.parse(File.read(Rails.root.join("test/fixtures/files/a-world-with-an-interior.yml")))
    story = WorldSeed::Loader.new(seed.deep_dup).load!

    assert_empty EngineSweep::Invariants.new(story, seed: seed).check
  end

  # --- and the corner the file stands a row in, since slice 4 ---------------

  # A CELL THAT MOVED IN PLACE IS THE ONE THING NOTHING ELSE HERE CAN SEE. The
  # room, the layer and the name are all untouched, so `items_accounted` and the
  # room half of this invariant stay quiet, and `positions_in_bounds` clears
  # every cell of the taproom but the ones outside it -- so a defect that
  # re-rolled the world's own corner would walk clean if the file's pair were
  # not read back. It is `geometry_unmoved`'s sentence one containment level
  # down.
  test "a world item whose cell moved during a walk is caught after it" do
    seed, story = interior_world

    Item.in_story(story).templates.find_by(name: "brass tap key").update!(x: 4, y: 1)

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "world_items_unmoved", broken.invariant
    assert_match(/brass tap key .* at 4,1 and the file says in The Taproom at 5,1/, broken.to_s)
  end

  test "a character whose cell moved during a walk is caught after it" do
    seed, story = interior_world

    story.characters.find_by(fullname: "Nell Cawsand").update!(x: 3, y: 6)

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "cast_unmoved", broken.invariant
    assert_match(/Nell Cawsand is in The Taproom at 3,6 and the file says in The Taproom at 2,6/, broken.to_s)
  end

  # BOTH WAYS, like the box one level up: a row that ACQUIRED a corner the file
  # does not give it fails exactly as loudly as one that lost the corner it was
  # written with -- which is what keeps this quiet on the three checked-in
  # worlds, where the file seats nobody and no row carries a cell.
  test "a world row that gained a cell the file does not give it is caught too" do
    seed, story = interior_world
    seed["locations"].detect { |row| row["name"] == "The Taproom" }["items"].sole.except!("x", "y")

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "world_items_unmoved", broken.invariant
    assert_match(/at 5,1 and the file says in The Taproom$/, broken.to_s.split("; ").first)
  end

  # AND ONE GAME'S OWN COPY IS DELIBERATELY NOT HELD TO THE FILE, because a walk
  # is SUPPOSED to move that cell: a drop rolls a new one, which is
  # `positions_in_bounds`' business and is why that invariant alone is not
  # stated against the file.
  test "a playthrough's own copy moved to another cell breaks nothing" do
    seed, story = interior_world
    taproom = story.locations.find_by(name: "The Taproom")
    template = Item.in_story(story).templates.find_by(name: "brass tap key")
    create(:item, character: nil, location: taproom, template: template, name: template.name,
                  playthrough: create(:playthrough, story: story, character: story.protagonist,
                                      current_location: taproom, current_scene: story.opening_scene),
                  x: 1, y: 5)

    assert_empty EngineSweep::Invariants.new(story, seed: seed).check
  end

  # THE INVARIANT ACROSS AN ACTUAL WALK, ON A WORLD THAT HAS GEOMETRY, and it is
  # the one this slice most wants: the two assertions above load and check
  # without taking a turn, and the only scripted walk is over a flat world where
  # both sides of every comparison are nil -- so it would hold even if the two
  # readers disagreed about a box entirely.
  #
  # NOT A SCRIPT, because `EngineSweep::Script` resolves a world by slug out of
  # `db/seeds/worlds/` and the captain's fourth ruling leaves those three flat.
  # `Playthrough::Mechanics` with `model: false` is what a script's step runs
  # anyway (`EngineSweep::Walk#engine_for`), so the typed lines below go through
  # the same engine the browser moves the world with.
  #
  # THE MOVE IS BETWEEN TWO CHILDREN OF ONE PLACE -- out of the taproom, into
  # the back room and back again -- which is the case the whole programme exists
  # for, and it must leave all six facts about all four rooms exactly as the
  # file wrote them.
  test "typed lines that move the party between two rooms of one place move no wall" do
    seed = WorldSeed.parse(File.read(Rails.root.join("test/fixtures/files/a-world-with-an-interior.yml")))
    story = WorldSeed::Loader.new(seed.deep_dup).load!
    game = Playthrough.create!(story: story, character: story.protagonist,
                               current_location: story.locations.realized.order(:id).first,
                               current_scene: story.opening_scene)
    engine = Playthrough::Mechanics.new(game, model: false)

    [ "go to The Back Room", "look", "go to The Taproom" ].each do |typed|
      report = engine.run(typed)

      assert_not report.refused?, "#{typed.inspect} was refused: #{report.refusal}"
    end

    assert_equal "The Taproom", game.reload.current_location.name
    assert_equal 2, story.locations.where.not(parent_location_id: nil).count
    assert_empty EngineSweep::Invariants.new(story, seed: seed).check
  end

  # THE LOADER RESOLVES A `parent` KEY ON `WorldSeed.natural_key`, so a file may
  # spell it with or without its article and still name one place. The invariant
  # has to read it the same way, or a world the format accepts would break a
  # walk that touched nothing.
  test "a parent key spelled with a different article leaves the invariant quiet" do
    seed = WorldSeed.parse(File.read(Rails.root.join("test/fixtures/files/a-world-with-an-interior.yml")))
    seed["locations"].each { |row| row["parent"] = "rusted anchor" if row["parent"] }
    story = WorldSeed::Loader.new(seed.deep_dup).load!

    assert_empty EngineSweep::Invariants.new(story, seed: seed).check
  end

  # --- positions_in_bounds --------------------------------------------------
  #
  # THE ONE INVARIANT THAT IS NOT STATED AGAINST THE FILE, because a walk is
  # SUPPOSED to move a position: a take clears one and a drop rolls a new one.
  # What a player may never do is put a thing somewhere its room is not.

  test "a world whose file places things inside their rooms walks with the invariant quiet" do
    seed = WorldSeed.parse(File.read(Rails.root.join("test/fixtures/files/a-world-with-an-interior.yml")))
    story = WorldSeed::Loader.new(seed.deep_dup).load!

    assert_empty EngineSweep::Invariants.new(story, seed: seed).check
  end

  # STRAIGHT TO THE COLUMNS, because `Item` refuses this: the invariant exists
  # for a state a WALK could write, and the only way to reach it in a test is
  # the way a defect would -- past the validation.
  test "a thing outside its room breaks positions_in_bounds" do
    seed, story = interior_world
    key = Item.in_story(story).templates.by_name("brass tap key").sole
    key.update_columns(x: 40, y: 40)

    # TWO SENTENCES ARE TRUE OF THIS ROW and both are reported: it is outside
    # the room it is in, AND it is no longer in the corner the file lays it in
    # (`world_items_unmoved`). One is about the records on their own and the
    # other is about the file, so this asks for the one it is testing.
    broken = EngineSweep::Invariants.new(story, seed: seed).check
                                    .find { |failure| failure.invariant == "positions_in_bounds" }

    assert broken, "nothing reported a thing lying through a wall"
    assert_match(/brass tap key/, broken.to_s)
    assert_match(/The Taproom is 7x8 paces at 0,0 on storey 0/, broken.to_s)
  end

  # BOTH ITEM LAYERS, because one game's copy in the wrong half of a room is as
  # wrong as the world's own row doing it -- and the report names which.
  test "one game's own copy outside its room breaks it too" do
    seed, story = interior_world
    game = Playthrough.create!(story: story, character: story.protagonist,
                               current_location: story.locations.find_by(name: "The Taproom"),
                               current_scene: story.opening_scene)
    copy = game.items.by_name("brass tap key").sole
    copy.update_columns(x: 40, y: 40)

    broken = EngineSweep::Invariants.new(story, seed: seed).check.sole

    assert_equal "positions_in_bounds", broken.invariant
    assert_match(/playthrough ##{game.id}/, broken.to_s)
  end

  test "somebody standing outside their room breaks it" do
    seed, story = interior_world
    story.protagonist.update_columns(x: 40, y: 40)

    broken = EngineSweep::Invariants.new(story, seed: seed).check
                                    .find { |failure| failure.invariant == "positions_in_bounds" }

    assert broken, "nothing reported somebody standing through a wall"
    assert_match(/Nell Cawsand/, broken.to_s)
  end

  # A ROOM WITH NO PLANE TO READ IT IN, which is the second of the three faults
  # this one sentence covers.
  test "a position in a room with no box breaks it" do
    seed, story = interior_world
    key = Item.in_story(story).templates.by_name("brass tap key").sole
    key.update_columns(location_id: story.locations.find_by(name: "The Harbour Road").id, x: 1, y: 1)

    broken = EngineSweep::Invariants.new(story, seed: seed).check
                                    .find { |failure| failure.invariant == "positions_in_bounds" }

    assert_match(/The Harbour Road has no box/, broken.to_s)
  end

  # AND HALF A POSITION, which is the third: `Item.positioned` takes a row
  # carrying EITHER column so that a partial one is caught here rather than
  # read as unplaced.
  test "half a position breaks it" do
    seed, story = interior_world
    Item.in_story(story).templates.by_name("brass tap key").sole.update_columns(y: nil)

    broken = EngineSweep::Invariants.new(story, seed: seed).check
                                    .find { |failure| failure.invariant == "positions_in_bounds" }

    assert broken, "nothing reported half a position"
    assert_match(/part-placed/, broken.to_s)
  end

  # UNPLACED IS NOT A BREAK, and it is what every row in the three checked-in
  # worlds is: a flat world has no plane for anything to be in.
  test "clearing a position leaves the invariant quiet" do
    seed, story = interior_world
    Item.in_story(story).templates.by_name("brass tap key").sole.update_columns(x: nil, y: nil)

    assert_empty EngineSweep::Invariants.new(story, seed: seed).check
                                        .select { |failure| failure.invariant == "positions_in_bounds" }
  end

  # The one world in the repository whose file places things, loaded with the
  # file it came from -- which is what the invariants compare against.
  def interior_world
    seed = WorldSeed.parse(File.read(Rails.root.join("test/fixtures/files/a-world-with-an-interior.yml")))

    [ seed, WorldSeed::Loader.new(seed.deep_dup).load! ]
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

  # A PLACE WITH A FOOTPRINT AND ONE PLACED ROOM PER NAME GIVEN, then the one
  # invariant this is about, or nil. Fixed coordinates and never rolled -- the
  # west half and then the east, so the two rooms are beside each other and not
  # on top of each other (`test/factories/location_connections.rb`'s rule).
  def room_names_checked(seed, story, names)
    place = create(:location, :stub, :with_a_footprint, story: story, name: "The Custom House")
    names.each_with_index do |name, index|
      create(:location, :stub, story: story, name: name, parent_location: place,
                               x: index * 6, y: 0, z: 0, width: 6, depth: 8)
    end

    EngineSweep::Invariants.new(story, seed: seed).check.find { |row| row.invariant == "room_names_unique" }
  end

  def connect(from, to)
    [ [ from, to ], [ to, from ] ].each do |origin, destination|
      create(:location_connection, location: origin, connected_location: destination,
                                   distance: "adjacent", travel_method: "walking")
    end
  end
end
