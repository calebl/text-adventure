require "test_helper"

# THE VERIFICATION OF THE HAND-WRITTEN LABELS, run in CI.
#
# A corpus of three hundred labels is only worth what its checking is worth, and
# the part a person can get wrong is not the English -- it is naming a thing
# that is not in reach. So every `target` and every `also_named` in
# `classifier_corpus.yml` is checked back against the closed set the action
# really reads at the position the line is played from, and a label that does
# not fit fails the build.
#
# IT COSTS NOTHING. Each position is staged offline out of its own copy of a
# seeded world, inside a transaction that is rolled back, with
# `BaseAgent.new` replaced so a model call from anywhere raises -- the same
# three guarantees `rake game:sweep` runs on. No key, no network, no spend.
class Eval::Classifier::CorpusTest < ActiveSupport::TestCase
  test "every labelled line names something that is actually in reach where it is played" do
    problems = EngineSweep.without_a_model { Eval::Classifier.corpus.problems }

    assert_empty problems, <<~FAILED
      #{Eval::Classifier::CORPUS} does not validate. Each line below names a target or an
      `also_named` that is not in the closed set its action reads at its position, or states
      a refusal its own intent/target/also_named do not imply:

      #{problems.join("\n")}
    FAILED
  end

  test "the corpus is big enough and broad enough to be a measurement" do
    corpus = Eval::Classifier.corpus

    assert_operator corpus.size, :>=, 250, "the corpus shrank below what a rate can be read off"
    assert_operator corpus.positions.size, :>=, 8, "fewer positions means fewer closed sets exercised"
    assert_equal Eval::Classifier::INTENTS.sort, corpus.lines.map(&:intent).uniq.sort,
                 "every intent in the schema has to be labelled somewhere, or the confusion matrix has a blank row"
  end

  # THE SHAPES THE RULING OF 2026-09-04 MADE LOAD-BEARING. Each of these is a
  # thing the corpus exists to measure, and a corpus that lost one would still
  # print a rate -- which is exactly the failure `Eval::Board` calls
  # "unavailable, never zero".
  test "the corpus holds every shape the refusal ruling turns on" do
    corpus = Eval::Classifier.corpus

    assert_operator corpus.lines.count { |line| line.refusal == :named_more_than_one }, :>=, 20,
                    "two acts on one line is the shape the ruling was made for"
    assert_operator corpus.lines.count { |line| line.refusal == :unresolved }, :>=, 20,
                    "a reach that finds nothing is the other half of the ruling"
    assert_operator corpus.by_shape.fetch("two-sets", []).size, :>=, 5,
                    "the cross-set gap one-act-per-line.yml pins has to be pinned here too"
    assert_operator corpus.by_shape.fetch("examine-nothing", []).size, :>=, 8,
                    "an examine that lands on nothing must NOT be refused, and that needs measuring"
    assert_operator corpus.by_shape.fetch("other", []).size, :>=, 15,
                    "an `other` must NOT be refused either"
  end

  # THE SAME LINE AT THE SAME POSITION TWICE is one measurement counted twice,
  # and it is the easiest thing to do wrong in a file this size -- two of them
  # were in the first draft, both because a line lifted from a stored
  # conversation was already there under a different id.
  #
  # BYTE-FOR-BYTE, and deliberately: `TAKE THE WARD STAMP` and
  # `take the ward stamp` are two measurements, because whether case matters is
  # one of the things this corpus is FOR, and so is
  # `"   go    to   the   supply   closet   "` against the same line squeezed.
  test "no line is the same typed line at the same position as another" do
    duplicates = Eval::Classifier.corpus.lines
                                 .group_by { |line| [ line.position, line.typed ] }
                                 .select { |_key, group| group.size > 1 }

    assert_empty duplicates.transform_values { |group| group.map(&:id) },
                 "the same line at one position is one measurement counted twice"
  end

  test "every line says what it is for" do
    corpus = Eval::Classifier.corpus

    assert_empty corpus.lines.select { |line| line.why.to_s.strip.empty? }.map(&:id),
                 "a label with no `why` is a label nobody can audit -- see the file's header"
    assert_empty corpus.lines.select { |line| line.shape.to_s.strip.empty? }.map(&:id),
                 "a line with no `shape` is invisible on the board's per-shape table"
  end

  # `unreadable` IS DELIBERATELY ABSENT and this is where that is stated rather
  # than left to be noticed: it is an `intent` outside the closed enum, so no
  # typed line can provoke it. `Playthrough::RefusalTest` covers it from the
  # other side.
  test "no line claims the unreadable refusal, which a typed line cannot cause" do
    assert_empty Eval::Classifier.corpus.lines.select { |line| line.refusal == :unreadable },
                 "an `unreadable` answer is a provider ignoring a closed enum, not a line a player can type"
  end

  test "a label naming something out of reach is caught" do
    broken = written(<<~YML)
      positions:
      - id: office
        story: The Unrecorded Hour
        room: Ward Office 12
      lines:
      - id: out-of-reach
        position: office
        typed: take the apron
        intent: take
        target: copy-room apron
        why: the apron is in the closet, not the office
    YML

    problems = EngineSweep.without_a_model { Eval::Classifier::Corpus.load(broken).problems }

    assert_equal 1, problems.size, problems.inspect
    assert_match(/out-of-reach: target "copy-room apron" is not in the closed set a take reads against/, problems.first)
  end

  test "a stated refusal that the label does not imply is caught" do
    broken = written(<<~YML)
      positions:
      - id: office
        story: The Unrecorded Hour
        room: Ward Office 12
      lines:
      - id: disagrees
        position: office
        typed: wait
        intent: other
        refusal: unresolved
        why: an `other` reaches for nothing, so it is never unresolved
    YML

    problems = Eval::Classifier::Corpus.load(broken).problems

    assert_equal 1, problems.size, problems.inspect
    assert_match(/the two readings of this line disagree/, problems.first)
  end

  test "a second name equal to the first is caught, because the app collapses it" do
    broken = written(<<~YML)
      positions:
      - id: closet
        story: The Unrecorded Hour
        room: The Supply Closet
      lines:
      - id: same-twice
        position: closet
        typed: take the index and the index
        intent: take
        target: Perrin's private index
        also_named: Perrin's private index
        refusal: named_more_than_one
        why: Playthrough::Classifier#also_record compares records and answers nil
    YML

    problems = Eval::Classifier::Corpus.load(broken).problems

    assert(problems.any? { |problem| problem.include?("also_named is the same name as target") }, problems.inspect)
  end

  test "an intent outside the schema does not load at all" do
    broken = written(<<~YML)
      positions:
      - id: office
        story: The Unrecorded Hour
        room: Ward Office 12
      lines:
      - id: not-an-intent
        position: office
        typed: dance
        intent: caper
        why: caper is not in Playthrough::IntentSchema::INTENTS
    YML

    error = assert_raises(Eval::Classifier::Corpus::Invalid) { Eval::Classifier::Corpus.load(broken) }
    assert_match(/intent :caper/, error.message)
  end

  # THE PAIR IS A SET. Nothing in the app decides which of two named things is
  # `target`, so a bench that scored the order would be scoring the labeller --
  # see `Eval::Classifier::Corpus::Answer`.
  test "a two-name answer matches whichever way round it comes back" do
    line = Eval::Classifier.corpus.lines.find { |row| row.refusal == :named_more_than_one }
    swapped = Eval::Classifier::Corpus::Answer.new(intent: line.intent, target: line.also_named,
                                                   also_named: line.target)

    assert line.accepts?(swapped), "#{line.id} should accept its own pair in either order"
  end

  test "the refusal a label implies is derived in the order the engine decides it" do
    assert_equal :named_more_than_one,
                 Eval::Classifier::Corpus.implied_refusal(intent: :take, target: "a", also_named: "b")
    assert_equal :unresolved, Eval::Classifier::Corpus.implied_refusal(intent: :take, target: nil, also_named: nil)
    assert_equal :none, Eval::Classifier::Corpus.implied_refusal(intent: :examine, target: nil, also_named: nil),
                 "an examine that lands on nothing is not a reach that missed -- see Playthrough::Drift::ACTIONS"
    assert_equal :none, Eval::Classifier::Corpus.implied_refusal(intent: :other, target: nil, also_named: nil)
  end

  private

  def written(body)
    file = Tempfile.new([ "classifier_corpus", ".yml" ])
    file.write(body)
    file.close
    file.path
  end
end
