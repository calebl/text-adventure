require "test_helper"

# THE RULE THAT DECIDES WHETHER A DIFFERENCE IS REAL, tested against the thing
# it is most likely to get wrong: nothing happening.
#
# The failure mode this guards is not a wrong p-value, it is a verdict of REAL
# on two sets of runs that differ only in what the models sampled. That would
# hand the captain exactly the false confidence the module was written to
# prevent, so the null cases below matter more than the positive ones.
class Eval::NoiseTest < ActiveSupport::TestCase
  # The real thing, from the four-arm whole-run sweep: three repetitions of one
  # unchanged configuration each, eleven turns apiece.
  # `third_person_protagonist` flags.
  MEASURED = {
    "mistral" => [ 3, 3, 6 ], "gemini" => [ 3, 0, 0 ],
    "kimi" => [ 6, 3, 2 ], "minimax" => [ 2, 1, 0 ]
  }.freeze

  test "a spread reports the min, the max and the median of runs that should have agreed" do
    band = Eval::Noise.spread(:third_person_protagonist, MEASURED.fetch("kimi"))

    assert_equal 3, band.runs
    assert_equal 2, band.min
    assert_equal 6, band.max
    assert_equal 3, band.median
    assert_equal 4, band.range
  end

  # THE HEADLINE FINDING, kept as a test so it cannot quietly stop being true:
  # one unchanged configuration moves by up to four flags on eleven turns.
  test "the measured within-arm spread is as wide as the differences anybody wants to claim" do
    ranges = MEASURED.transform_values { |values| Eval::Noise.spread(:x, values).range }

    assert_operator ranges.values.max, :>=, 3, "the noise floor got narrower: #{ranges.inspect}"
    assert_operator ranges.values.min, :>=, 2, "every arm moved by at least two: #{ranges.inspect}"
  end

  # ------------------------------------------------------------------ null
  test "identical sets of runs are never called real" do
    verdict = Eval::Noise.compare(:item_not_held, [ 0.1, 0.2, 0.1, 0.0, 0.2 ], [ 0.1, 0.2, 0.1, 0.0, 0.2 ])

    assert verdict.noise?
    assert_equal 1.0, verdict.p_value
  end

  test "two halves of one unchanged configuration are called noise, not real" do
    pooled = MEASURED.values.flatten.map { |count| count / 11.0 }
    verdict = Eval::Noise.compare(:third_person_protagonist, pooled.first(6), pooled.last(6))

    assert_not verdict.real?, "splitting one configuration in half must not manufacture a result"
  end

  test "runs that all flagged nothing are noise rather than a perfect improvement" do
    verdict = Eval::Noise.compare(:truncated_prose, [ 0.0 ] * 5, [ 0.0 ] * 5)

    assert verdict.noise?
    assert_equal 0.0, verdict.delta
  end

  # ------------------------------------------------------------------ signal
  test "a clean separation at five runs a side is real" do
    verdict = Eval::Noise.compare(:item_not_held, [ 0.30, 0.28, 0.33, 0.31, 0.29 ], [ 0.10, 0.09, 0.12, 0.08, 0.11 ])

    assert verdict.real?, verdict.headline
    assert verdict.improved?
    assert verdict.exact
    assert_in_delta 2 / 252.0, verdict.p_value, 0.0001,
                    "5 v 5 has 252 arrangements and a two-sided test counts both extremes"
  end

  test "the direction is reported, so a change that made things worse cannot read as a win" do
    verdict = Eval::Noise.compare(:item_not_held, [ 0.10, 0.09, 0.12, 0.08, 0.11 ], [ 0.30, 0.28, 0.33, 0.31, 0.29 ])

    assert verdict.real?
    assert_not verdict.improved?
    assert_operator verdict.delta, :>, 0
  end

  # ------------------------------------------------------------ inconclusive
  test "three runs a side gets no verdict, because the test cannot reach ALPHA there" do
    verdict = Eval::Noise.compare(:item_not_held, [ 0.3, 0.3, 0.3 ], [ 0.0, 0.0, 0.0 ])

    assert verdict.inconclusive?
    assert_nil verdict.p_value
  end

  # MIN_RUNS IS ARITHMETIC, NOT TASTE. At three a side a perfect separation
  # cannot clear ALPHA, so a verdict there would be reporting the sample size.
  test "three runs a side cannot reach ALPHA even when the separation is perfect" do
    at_three, = Eval::Noise.significance([ 1.0, 1.1, 1.2 ], [ 2.0, 2.1, 2.2 ])
    at_four, = Eval::Noise.significance([ 1.0, 1.1, 1.2, 1.3 ], [ 2.0, 2.1, 2.2, 2.3 ])

    assert_in_delta 0.10, at_three, 0.0001
    assert_operator at_three, :>, Eval::Noise::ALPHA
    assert_operator at_four, :<, Eval::Noise::ALPHA
    assert_equal 4, Eval::Noise::MIN_RUNS
  end

  # THE BAND IS WHAT SEPARATES "NOISE" FROM "WE CANNOT SAY". It is the wider of
  # the two sides' own ranges: whatever one unchanged configuration produced on
  # its own needs no explaining.
  test "the noise band is the wider of the two sides' own ranges" do
    verdict = Eval::Noise.compare(:item_not_held, [ 0.00, 0.10, 0.05, 0.02, 0.60 ], [ 0.30, 0.30, 0.31, 0.29, 0.30 ])

    assert_in_delta 0.60, verdict.band, 0.0001
    assert_not verdict.real?, verdict.headline
    assert verdict.noise?, "a gap inside a band that wide is not evidence: #{verdict.headline}"
  end

  test "a check that no run could answer gets no verdict" do
    verdict = Eval::Noise.compare(:unreachable_transition, [], [])

    assert verdict.inconclusive?
    assert_equal 0, verdict.before.runs
  end

  # ------------------------------------------------------------------ maths
  test "the exact test is used where the arrangements can be counted and says so" do
    _, exact = Eval::Noise.significance([ 1, 2, 3, 4, 5 ], [ 6, 7, 8, 9, 10 ])

    assert exact
  end

  test "large sets fall back to the approximation rather than enumerating forever" do
    left = Array.new(20) { |index| index }
    right = Array.new(20) { |index| index + 100 }

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    probability, exact = Eval::Noise.significance(left, right)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_not exact
    assert_operator probability, :<, 0.001
    assert_operator elapsed, :<, 1.0
  end

  test "ties are handled by ranking rather than by ignoring them" do
    probability, = Eval::Noise.significance([ 1, 1, 1, 1 ], [ 1, 1, 1, 1 ])

    assert_equal 1.0, probability
  end
end
