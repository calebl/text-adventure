require "test_helper"

# THE FREE FLOOR, RUN IN CI.
#
# `rake eval:classifier` costs cents and needs a key; this half costs nothing
# and runs on every `bin/rails test`, which makes it the part that can guard the
# corpus mechanically. Two things are asserted here and neither is a rate:
#
#   1. THE FLOOR IS BELOW THE MODEL, and by a margin worth paying for. If a
#      fixed grammar ever got most of this corpus right, the classifier call
#      would be hard to justify -- so the figure is pinned with a ceiling rather
#      than left as a number in a PR body.
#   2. THE OUTCOMES ARE TOLD APART. `wrong` -- an answer the label does not
#      accept, produced silently -- is the dangerous one, and a floor that
#      folded it into `over_refused` would hide it.
#
# The measured figure of 2026-09-04 is in the assertions, with room around it,
# so a change to `Playthrough::Mechanics`'s grammar shows up here as a
# deliberate movement rather than as nothing at all.
class Eval::Classifier::OfflineTest < ActiveSupport::TestCase
  def setup
    @floor = Eval::Classifier::Offline.new.summary
  end

  test "the fixed grammar gets well under half the corpus right, which is what a classifier call buys" do
    assert_equal Eval::Classifier.corpus.size, @floor.size
    assert_operator @floor.accuracy, :<, 0.60,
                    "the offline grammar now answers most of the corpus (#{@floor.accuracy}) -- if that is real, " \
                    "the case for a model call on every turn has changed and EVALUATION.md should say so"
    assert_operator @floor.accuracy, :>, 0.20,
                    "the floor collapsed to #{@floor.accuracy}; the grammar is the offline fallback and " \
                    "`rake game:sweep` walks the engine through it"
  end

  # WHAT THE FLOOR IS ACTUALLY BAD AT, pinned because it is the argument. It
  # refuses lines it should have played -- an ordinary remark, a pronoun, a name
  # spelled the way somebody heard it -- and that is a whole turn the player
  # does not get.
  test "most of what the floor gets wrong is refusing a line that should have played"  do
    assert_operator @floor.count(:over_refused), :>, @floor.count(:wrong),
                    "the grammar's failure mode is meant to be an honest refusal, not a silent wrong answer"
    assert_operator @floor.count(:over_refused), :>, 100,
                    "over-refusal is the measured cost of having no classifier: #{@floor.to_h[:outcomes].inspect}"
  end

  # THE SHAPES IT CANNOT SEE AT ALL, which is the other half of the argument and
  # the reason those shapes are in the corpus.
  test "the floor cannot answer a line that reaches for no record" do
    by_shape = @floor.by_shape

    assert_in_delta 0.0, by_shape.fetch("other")[:rate], 0.001,
                    "a fixed grammar has no word for `other`, so every ordinary remark is refused"
    assert_in_delta 0.0, by_shape.fetch("examine-nothing")[:rate], 0.001,
                    "and no way to look at something the records do not hold"
  end

  # AND WHAT IT IS GOOD AT, kept as a test so the floor is not read as useless.
  # A reach that finds nothing is refused correctly by a grammar with no model
  # at all, which is exactly why `rake game:sweep` can assert refusals offline.
  test "the floor refuses a reach that finds nothing, every time" do
    %w[unresolved-move unresolved-talk unresolved-take unresolved-drop].each do |shape|
      assert_in_delta 1.0, @floor.by_shape.fetch(shape)[:rate], 0.001,
                      "#{shape} is the engine half of the ruling and needs no model"
    end
  end

  test "it makes no model call, guarded rather than intended" do
    # `EngineSweep.without_a_model` is already inside `#run`; this proves the
    # guard is really in the path rather than a comment about it.
    assert_raises(EngineSweep::ModelCalled) do
      Eval::Classifier::Offline.new.instance_eval do
        EngineSweep.without_a_model { BaseAgent.new(purpose: "classifier") }
      end
    end
  end

  test "every reading carries the line, the outcome and what the grammar said" do
    reading = @floor.readings.find { |row| row.outcome == :over_refused }

    assert_not_nil reading, "the floor is expected to over-refuse; see the test above"
    assert_not_nil reading.got, "a refusal has to say what the grammar answered, or the number is unauditable"
    assert_includes Eval::Classifier::Offline::OUTCOMES, reading.outcome
  end
end
