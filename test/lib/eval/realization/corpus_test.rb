require "test_helper"

# THE CHECKED-IN CORPUS, VERIFIED AGAINST THE WORLDS IT NAMES.
#
# This is the test that makes the corpus a measurement rather than a claim: a
# case whose room, neighbour or absent world has been renamed would otherwise
# fail at spend time, in the middle of a paid run, as a hole in a pass. It runs
# offline and makes no model call -- staging is a seed load and row surgery --
# which is the same bargain `Eval::Classifier::CorpusTest` and
# `Eval::Prompt::CorpusTest` strike.
class Eval::Realization::CorpusTest < ActiveSupport::TestCase
  test "the checked-in corpus validates against the worlds it names" do
    problems = Eval::Realization.corpus.problems

    assert_empty problems, "the realization corpus does not validate:\n  #{problems.join("\n  ")}"
  end

  test "every world the corpus names has a file, and the generated one is not a seeded world" do
    Eval::Realization.corpus.stories.each do |story|
      assert_not_nil Eval::Realization.world_file(story), story
    end

    iron_gate = Eval::Realization.world_file("The Iron Gate Descends")
    assert_equal "test/fixtures/files/worlds", iron_gate.dirname.relative_path_from(Rails.root).to_s,
                 "a generated world under db/seeds/worlds would be loaded into every development database"
  end

  # THE CORPUS REACHES THE CASES IT WAS BUILT TO REACH. A file that quietly lost
  # its only dangerous room, or its only dead end, would still validate and
  # would silently stop measuring the thing it exists for.
  test "the corpus still carries every shape the bench was built to measure" do
    shapes = Eval::Realization.corpus.by_shape.keys

    %w[written-neighbour unwritten-neighbour dead-end descent dangerous landmark two-ways-out
       interior-room].each do |shape|
      assert_includes shapes, shape
    end
  end

  # AND THE SHAPE THAT IS A CLAIM ABOUT THE ROOM RATHER THAN ABOUT THE WORLD
  # AROUND IT. An `interior-room` case exists to put a FLOOR PLAN in the detail
  # prompt and to make no exits call at all; a case whose room lost its box, its
  # parent or its doors in the staging would keep the name and measure an
  # ordinary room.
  test "an `interior-room` case stands up inside a place, with its plan and every door it was laid out with" do
    cases = Eval::Realization.corpus.for_shape("interior-room").cases

    assert_predicate cases, :any?
    Eval::Realization::Stage.open(cases) do |stages|
      cases.each do |kase|
        standing = stages.fetch(kase.id)
        plan = standing.plan

        assert_not_nil plan, "#{kase.id}: a room with no plan is not an interior room"
        assert_equal standing.location.exits.count,
                     plan["doors"].size + plan["stairs"].size + plan["other_ways_out"].size,
                     "#{kase.id}: every edge the layout wrote is still on the records and described"
        assert_operator standing.location.exits.count, :>, 1,
                        "#{kase.id}: the doors of a laid-out room are not wound back to the way in"
      end
    end
  end

  # A SHAPE IS A CLAIM ABOUT WHAT THE STAGE PRODUCES, not a string. `two-ways-out`
  # exists so `exit_already_reachable` and `exit_over_the_allowance` meet a stub
  # that is ALREADY partly connected, and a case whose second edge was dropped in
  # the staging would stand up as an ordinary one-way-out room, keep its name and
  # measure nothing. So the shape is asserted against the world it stages.
  test "a `two-ways-out` case really stands up with more than one way out and less than the full allowance" do
    cases = Eval::Realization.corpus.for_shape("two-ways-out").cases

    assert_predicate cases, :any?
    Eval::Realization::Stage.open(cases) do |stages|
      cases.each do |kase|
        standing = stages.fetch(kase.id)

        assert_operator standing.reachable.size, :>, 1,
                        "#{kase.id} says the stub already reaches two places: #{standing.reachable.inspect}"
        assert_includes standing.reachable, kase.reached_from
        kase.also_reaches.each { |name| assert_includes standing.reachable, name }
        assert_equal Location::ExitsSchema::MAX_EXITS - standing.reachable.size, standing.exit_allowance,
                     "#{kase.id}: the prompt states what is LEFT, so a partly connected stub is below the cap"
      end
    end
  end

  # THE OTHER SHAPE WHOSE `why` IS A CLAIM ABOUT THE STAGING. `written-neighbour`
  # exists so `exit_into_a_written_room` meets a place that is written and out of
  # reach, and the thing a reader gets wrong about it is which place that is:
  # `Location::Generator#known_location_line` marks a place only when it is
  # realized AND unreachable, so the way back -- connected by construction -- is
  # never marked however written it is. Asserted against the prompt the case
  # really sends, so a `why` that drifts from the staging has something to fail.
  test "a `written-neighbour` case stages a marked place, and never marks the way back" do
    cases = Eval::Realization.corpus.for_shape("written-neighbour").cases

    assert_predicate cases, :any?
    Eval::Realization::Stage.open(cases) do |stages|
      cases.each do |kase|
        standing = stages.fetch(kase.id)
        marked = standing.places.select { |place| place["realized"] && !place["connected"] }
        prompt = standing.generator.exits_prompt

        assert_predicate marked, :any?,
                         "#{kase.id}: nothing is written and out of reach, so the shape reaches no defect"
        marked.each do |place|
          assert_includes prompt, "#{place["name"]} (already written -- do not open a new way into it)"
        end
        assert_not_includes prompt, "#{kase.reached_from} (already written",
                            "#{kase.id}: the way back is connected, so it is listed and never marked"
      end
    end
  end

  test "a case naming an `also_reaches` the room is not joined to is refused" do
    assert_problem "could not already reach it", <<~YML
      cases:
      - id: not-a-neighbour
        story: The Unrecorded Hour
        room: The Long Hallway
        reached_from: Ward Office 12
        also_reaches:
        - The Supply Closet
        expects_new_ground: true
        shape: two-ways-out
        why: nothing joins the hallway to the closet, so this stub never reached it
    YML
  end

  test "both worlds are represented and the held-out one is in it" do
    stories = Eval::Realization.corpus.stories

    assert_includes stories, Eval::HELD_OUT
    assert_includes stories, "The Iron Gate Descends", "the generated world is the one the defect was measured in"
    assert_operator Eval::Realization.corpus.size, :>=, 12, "a corpus this small is a corpus of anecdotes"
  end

  test "the digest moves when a case does and not when a `why` is rewritten" do
    corpus = Eval::Realization.corpus
    was = Eval::Realization.digest(corpus)

    assert_equal was, Eval::Realization.digest(corpus), "the digest of one corpus is one digest"
    assert_not_equal was, Eval::Realization.digest(corpus.subset { |kase| kase.story == Eval::HELD_OUT })

    reworded = with_cases(corpus) { |kase| kase.with(why: "#{kase.why} And a sentence nobody measures.") }
    assert_equal was, Eval::Realization.digest(reworded), "rewriting a `why` measures nothing new"
  end

  # EVERY FIELD THAT CHANGES WHAT WAS MEASURED HAS TO MOVE THE DIGEST, or
  # `rake eval:realization_compare` reports the movement it causes as a change in
  # the prompt. `expects_new_ground` decides whether `no_new_ground` is judgeable
  # and gates `exit_already_reachable`'s dead end; `shape` chooses the designated
  # case behind `prompt_digest`; `also_reaches` changes the world that is staged.
  test "editing a field that changes what was measured moves the digest" do
    corpus = Eval::Realization.corpus
    was = Eval::Realization.digest(corpus)

    { expects_new_ground: ->(kase) { !kase.expects_new_ground? },
      shape: ->(_kase) { "a-different-shape" },
      also_reaches: ->(_kase) { [ "Somewhere Else" ] },
      danger: ->(_kase) { "dangerous" },
      room: ->(_kase) { "A Different Room" } }.each do |field, change|
      edited = with_cases(corpus) { |kase|
        kase == corpus.cases.first ? kase.with(field => change.call(kase)) : kase
      }

      assert_not_equal was, Eval::Realization.digest(edited), field
    end
  end

  # THE PROMOTED CASE'S OWN FIELDS, EACH AGAINST THE DIGEST. `expects_inside`'s
  # precedent: an expectation decides which figures a case may be judged on, so
  # editing one moves the rates with no prompt touched -- and a comparison across
  # the edit would credit the movement to the prompt, which is the one failure
  # `Eval::Realization.digest` exists to prevent.
  test "every field a promoted case carries moves the digest" do
    corpus = Eval::Realization.corpus
    was = Eval::Realization.digest(corpus)

    { teaser: ->(_kase) { "A stone counting house half-sunk at the river's edge." },
      inside: ->(_kase) { "a few rooms" },
      population: ->(_kase) { Location::Population::LABELS.first },
      expects_danger_at_least: ->(_kase) { "uneasy" },
      expects: ->(_kase) { { "hazard" => [ "flooded" ] } } }.each do |field, change|
      edited = with_cases(corpus) { |kase|
        kase == corpus.cases.first ? kase.with(field => change.call(kase)) : kase
      }

      assert_not_equal was, Eval::Realization.digest(edited), field
    end
  end

  # AND THE EXPECTATION IS FOLDED AS A SET RATHER THAN AS A LIST: two files that
  # allow the same labels in a different order measured the same thing, so the
  # digest must not call them different corpora.
  test "reordering the labels of one expectation measures nothing new" do
    corpus = Eval::Realization.corpus
    one = with_cases(corpus) { |kase| kase.with(expects: { "hazard" => [ "flooded", "silent" ] }) }
    other = with_cases(corpus) { |kase| kase.with(expects: { "hazard" => [ "silent", "flooded" ] }) }

    assert_equal Eval::Realization.digest(one), Eval::Realization.digest(other)
  end

  # THE ORDINAL FLOOR IS EXPANDED TO THE RUNGS AT OR ABOVE IT, which is what
  # *"uneasy or worse"* means -- and it is read as an allowed set exactly like
  # every other key, so nothing downstream has to know it was written as one word.
  test "a danger floor reads as every rung at or above it, and don't care as nil" do
    ladder = Location::Parameters::LADDER
    kase = Eval::Realization::Corpus::Case.new(id: "a", story: "b", room: "c",
                                               expects_danger_at_least: ladder.second)

    assert_equal ladder[1..], kase.expects_for(Eval::Realization::Corpus.danger_pick)
    assert_equal ladder, Eval::Realization::Corpus::Case.new(id: "a", story: "b", room: "c",
                                                             expects_danger_at_least: ladder.first)
                                                        .expects_for("danger")
    assert_nil Eval::Realization::Corpus::Case.new(id: "a", story: "b", room: "c").expects_for("danger")
  end

  # A KEY LEFT OUT IS *DON'T CARE*, and it is the same rule `expects_inside`
  # already obeys: it takes the case out of that figure's numerator and its
  # denominator both, because a rate a check did not earn is worse than no rate.
  test "an `expects_*` key left out is don't care and a key written is read as a set" do
    corpus = Eval::Realization::Corpus.load(fixture_of(<<~YML))
      cases:
      - id: expecting
        story: The Unrecorded Hour
        room: The Long Hallway
        reached_from: Ward Office 12
        expects_new_ground: true
        expects_hazard:
        - flooded
        expects_exit_inside: a few rooms
        shape: corridor
        why: one key as a sequence, one as a bare string, and everything else left out
    YML
    kase = corpus.cases.sole

    assert_equal [ "flooded" ], kase.expects_for("hazard")
    assert_equal [ "a few rooms" ], kase.expects_for("inside")
    assert_nil kase.expects_for("storeys_below")
    assert_nil kase.expects_for("danger")
    assert_equal %w[hazard inside], kase.declared.map(&:name)
  end

  # THE VALIDATOR'S OWN CHECKS, each against a case written to trip it. A
  # validator nobody has seen fail is a validator nobody knows works.
  test "a case in a world this bench does not build rooms in is refused" do
    assert_problem "is not a world this bench builds rooms in", <<~YML
      cases:
      - id: nowhere
        story: A World That Is Not
        room: Anywhere
        expects_new_ground: true
        shape: landmark
        why: it names a world with no file
    YML
  end

  test "a case with no `expects_new_ground` is refused, because no_new_ground would be unjudgeable" do
    assert_problem "expects_new_ground", <<~YML
      cases:
      - id: undeclared
        story: The Unrecorded Hour
        room: The Long Hallway
        reached_from: Ward Office 12
        shape: corridor
        why: it never says whether the story points onward from here
    YML
  end

  test "a case whose room the world does not have is refused" do
    assert_problem "has no room called", <<~YML
      cases:
      - id: missing-room
        story: The Unrecorded Hour
        room: The Boiler Landing
        reached_from: Ward Office 12
        expects_new_ground: true
        shape: corridor
        why: the hallway was renamed and this case was not
    YML
  end

  test "a case claiming a way back that does not exist is refused" do
    assert_problem "not connected in this world", <<~YML
      cases:
      - id: unreachable
        story: The Unrecorded Hour
        room: The Long Hallway
        reached_from: The Supply Closet
        expects_new_ground: true
        shape: corridor
        why: nothing joins the hallway to the closet, so that is not the way it was reached
    YML
  end

  test "a case with no `why` and no `shape` is refused" do
    problems = problems_for(<<~YML)
      cases:
      - id: bare
        story: The Unrecorded Hour
        room: The Long Hallway
        reached_from: Ward Office 12
        expects_new_ground: true
    YML

    assert problems.any? { |problem| problem.include?("`shape`") }, problems.inspect
    assert problems.any? { |problem| problem.include?("`why`") }, problems.inspect
  end

  test "two cases with one id are refused" do
    assert_problem "is used more than once", <<~YML
      cases:
      - id: twice
        story: The Unrecorded Hour
        room: The Long Hallway
        reached_from: Ward Office 12
        expects_new_ground: true
        shape: corridor
        why: the first
      - id: twice
        story: The Unrecorded Hour
        room: The Supply Closet
        reached_from: Ward Office 12
        expects_new_ground: false
        shape: dead-end
        why: the second, under the same id
    YML
  end

  # ------------------------------------------------- a case that carries its own stub

  test "a case that carries a teaser stands its stub up in a world that never had it" do
    corpus = Eval::Realization::Corpus.load(fixture_of(TYPED))

    assert_empty corpus.problems
  end

  test "a case with a teaser and no danger is refused, because the roll is not reproducible" do
    assert_problem "needs a `danger`", TYPED.sub("  danger: uneasy\n", "")
  end

  test "a case with a teaser whose room the world already has is refused" do
    assert_problem "would write it twice", TYPED.sub("room: The Drowned Counting House",
                                                     "room: The Long Hallway")
  end

  test "an `inside` or a `population` on a case that finds its room is refused" do
    problems = problems_for(<<~YML)
      cases:
      - id: restating-the-world
        story: The Unrecorded Hour
        room: The Long Hallway
        reached_from: Ward Office 12
        inside: a few rooms
        population: a crowd
        expects_new_ground: true
        shape: corridor
        why: the hallway is in the world file already, so both of these are the world's own
    YML

    assert problems.any? { |problem| problem.include?("`inside`") }, problems.inspect
    assert problems.any? { |problem| problem.include?("`population`") }, problems.inspect
  end

  test "an `inside` band the table has no footprint for is refused" do
    assert_problem "inside \"a cathedral of rooms\"", TYPED.sub("inside: a few rooms",
                                                                "inside: a cathedral of rooms")
  end

  test "a `population` word the table has no band for is refused" do
    assert_problem "population \"teeming\"", TYPED.sub("population: a person or two",
                                                        "population: teeming")
  end

  # THE EXPECTATION'S OWN VALIDATION, and it is
  # `Lab::Realization::Kind#expectations_are_labels_the_model_is_offered`'s rule
  # one level up: the model cannot answer a word its schema's enum does not
  # carry, so a set holding one is a rate that can never be earned -- and it
  # would read on a board as the prompt failing rather than as a typo.
  test "an expectation naming a label the model is never offered is refused" do
    assert_problem "which is not on the list the model picks from",
                   TYPED.sub("  - flooded", "  - swarming with bees")
  end

  test "a danger floor that is not a rung of the ladder is refused" do
    assert_problem "is a rung of the ladder", TYPED.sub("expects_danger_at_least: uneasy",
                                                        "expects_danger_at_least: apocalyptic")
  end

  private

  # A CASE THAT CARRIES ITS OWN STUB, in full, so each test above can break one
  # key of it and nothing else.
  TYPED = <<~YML.freeze
    cases:
    - id: lab-the-drowned-counting-house
      story: The Unrecorded Hour
      room: The Drowned Counting House
      teaser: >-
        A counting house half-sunk at the river's edge, its ledgers still on the desks.
      reached_from: Ward Office 12
      inside: a few rooms
      population: a person or two
      danger: uneasy
      expects_new_ground: true
      expects_hazard:
      - flooded
      expects_danger_at_least: uneasy
      shape: lab-promoted
      why: >-
        Typed in the realization lab and scored there. The fixture the validator's own
        checks each break one key of.
  YML

  def assert_problem(fragment, body)
    problems = problems_for(body)

    assert problems.any? { |problem| problem.include?(fragment) },
           "expected a problem mentioning #{fragment.inspect}, got #{problems.inspect}"
  end

  def with_cases(corpus, &block)
    Eval::Realization::Corpus.new(path: corpus.path, cases: corpus.cases.map(&block))
  end

  def problems_for(body) = Eval::Realization::Corpus.load(fixture_of(body)).problems

  def fixture_of(body)
    file = Tempfile.new([ "realization_corpus", ".yml" ])
    file.write(body)
    file.close
    @fixtures = [ *@fixtures, file ]

    file.path
  end
end
