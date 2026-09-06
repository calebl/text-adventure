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

    %w[written-neighbour unwritten-neighbour dead-end descent dangerous landmark two-ways-out].each do |shape|
      assert_includes shapes, shape
    end
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

  private

  def assert_problem(fragment, body)
    problems = problems_for(body)

    assert problems.any? { |problem| problem.include?(fragment) },
           "expected a problem mentioning #{fragment.inspect}, got #{problems.inspect}"
  end

  def problems_for(body)
    file = Tempfile.new([ "realization_corpus", ".yml" ])
    file.write(body)
    file.close

    Eval::Realization::Corpus.load(file.path).problems
  end
end
