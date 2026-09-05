require "test_helper"

# THE VERIFICATION OF THE HAND-WRITTEN CASES, run in CI.
#
# A corpus of ninety cases is only worth what its checking is worth, and the
# part a person gets wrong is not the English -- it is naming a thing that is
# not in reach, or writing a case that would quietly buy a second model call.
# So every case is staged against the closed set its action really reads, and a
# case that does not fit fails the build.
#
# IT COSTS NOTHING. Each position is staged offline out of its own copy of a
# seeded world, inside a transaction that is rolled back, with `BaseAgent.new`
# replaced so a model call from anywhere raises -- the same three guarantees
# `rake game:sweep` runs on. No key, no network, no spend.
class Eval::Prompt::CorpusTest < ActiveSupport::TestCase
  test "every case acts on something that is actually in reach where it is played" do
    problems = EngineSweep.without_a_model { Eval::Prompt.corpus.problems }

    assert_empty problems, <<~FAILED
      #{Eval::Prompt::CORPUS} does not validate. Each case below names a target that is not
      in the closed set its action reads at its position, would be refused rather than
      narrated, or would buy a second model call:

      #{problems.join("\n")}
    FAILED
  end

  test "the corpus is big enough and broad enough to be a measurement" do
    corpus = Eval::Prompt.corpus

    assert_operator corpus.size, :>=, 60, "the corpus shrank below what a rate can be read off"
    assert_operator corpus.positions.size, :>=, 8, "fewer positions means fewer moments exercised"
    assert_equal %w[drop examine move other read take].sort, corpus.by_shape.keys.sort,
                 "every shape this bench measures has to be in the file, or a row of the board is blank"
  end

  # EVERY CHECK THIS BENCH CAN RUN HAS TO HAVE CASES IT CAN RUN ON. A check with
  # no judgeable case still prints -- as `unavailable` -- and a corpus that lost
  # the cases for one would quietly stop measuring it. The two transition checks
  # are the ones this bench was built for, so they carry a floor of their own.
  test "the corpus carries the cases every available check needs" do
    corpus = Eval::Prompt.corpus

    assert_operator corpus.cases.count { |kase| kase.act == :take }, :>=, 12,
                    "take_denied is the check this bench was built for"
    assert_operator corpus.cases.count { |kase| kase.act == :drop }, :>=, 12,
                    "pickup_invented is the other half of it"
    assert_operator corpus.cases.count(&:move?), :>=, 8,
                    "a move is the only shape that reaches the arrival pass at all"
    assert_operator corpus.by_shape.fetch("read", []).size, :>=, 8,
                    "inscription_misquoted needs turns that acted on a thing with words on record"
    assert_operator corpus.by_shape.fetch("other", []).size, :>=, 12,
                    "an `other` is the loosest prompt in the game and the one most likely to invent"
  end

  # BOTH WORLDS, AND THE HELD-OUT ONE IN QUANTITY. This bench exists so a prompt
  # can be tuned against a measurement, and a prompt tuned against every case in
  # the file is a prompt fitted to the file.
  test "the held-out world carries enough cases to read a result on" do
    corpus = Eval::Prompt.corpus
    held_out = corpus.cases.count { |kase| Eval::Prompt.held_out?(corpus.story_of(kase)) }

    assert_operator held_out, :>=, 25,
                    "The Salt Assizes is where a prompt change is confirmed, not where it is tuned"
    assert_operator corpus.size - held_out, :>=, 25, "and the tuning world needs cases too"
  end

  test "no case is written twice" do
    corpus = Eval::Prompt.corpus
    twice = corpus.cases.group_by { |kase| [ kase.position, kase.typed, kase.act ] }
                  .select { |_key, found| found.size > 1 }

    assert_empty twice.keys, "the same line at the same position is one measurement counted twice"
  end

  # ---------------------------------------------------------------- the rules

  test "a case naming something out of reach is refused" do
    problems = validate(<<~YML)
      positions:
      - id: office
        story: The Unrecorded Hour
        room: Ward Office 12
      cases:
      - id: reaching
        position: office
        typed: pick up the tide-slate
        act: take
        target: Assize tide-slate
        shape: take
        why: another world's item
    YML

    assert_equal 1, problems.size
    assert_match(/is not in the closed set a take reads against/, problems.sole)
  end

  test "a case the engine would refuse is not a case" do
    problems = validate(<<~YML)
      positions:
      - id: office
        story: The Unrecorded Hour
        room: Ward Office 12
      cases:
      - id: nothing-at-all
        position: office
        typed: go to the wine cellar
        act: move
        shape: move
        why: a door this world does not have
    YML

    assert_match(/REFUSED, not narrated/, problems.sole)
  end

  # THE TWO SHAPES THAT WOULD QUIETLY BUY A SECOND CALL, which is worse than an
  # expensive case: the extra call happens on the FIRST repetition only, so the
  # run's own repetitions would disagree for a reason that is not the model.
  test "a move to a stub is refused, because it would call Location::Generator" do
    problems = validate(<<~YML)
      positions:
      - id: office
        story: The Unrecorded Hour
        room: Ward Office 12
      cases:
      - id: into-the-hallway
        position: office
        typed: walk out into the long hallway
        act: move
        target: The Long Hallway
        shape: move
        why: the seeded stub
    YML

    assert_match(/is a stub, so this move would call Location::Generator/, problems.sole)
  end

  test "a world with a mechanic that moves the doorways is refused" do
    problems = validate(<<~YML)
      positions:
      - id: room-3
        story: The Lunar Cartographer
        room: Grenn's Boarding House, Room 3
      cases:
      - id: waiting
        position: room-3
        typed: wait
        act: other
        shape: other
        why: a world whose exits move on the clock
    YML

    assert_match(/is not a world this bench plays/, problems.sole)
  end

  test "a talk is refused, because there is no prompt version to measure it under" do
    problems = validate(<<~YML)
      positions:
      - id: office
        story: The Unrecorded Hour
        room: Ward Office 12
      cases:
      - id: talking
        position: office
        typed: ask him why he is early
        act: talk
        target: Halkett Rowe
        shape: talk
        why: the pass with no instructions
    YML

    assert_match(/does not measure a talk/, problems.sole)
  end

  test "a case with no why is refused, because a why is what makes it auditable" do
    problems = validate(<<~YML)
      positions:
      - id: office
        story: The Unrecorded Hour
        room: Ward Office 12
      cases:
      - id: unexplained
        position: office
        typed: wait
        act: other
        shape: other
    YML

    assert_match(/needs a `why`/, problems.sole)
  end

  test "an act the schema does not have is refused on the way in" do
    error = assert_raises(Eval::Prompt::Corpus::Invalid) do
      Eval::Prompt::Corpus.load(written(<<~YML))
        positions:
        - id: office
          story: The Unrecorded Hour
          room: Ward Office 12
        cases:
        - id: dancing
          position: office
          typed: dance
          act: dance
          shape: other
          why: not an intent
      YML
    end

    assert_match(/is not one of/, error.message)
  end

  private

  def validate(body)
    EngineSweep.without_a_model { Eval::Prompt::Corpus.load(written(body)).problems }
  end

  def written(body)
    file = Tempfile.new([ "prompt_corpus", ".yml" ])
    file.write(body)
    file.close
    file.path
  end
end
