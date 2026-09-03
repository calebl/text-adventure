# HOW FAR THESE NUMBERS WANDER WHEN NOTHING CHANGED, and the rule for deciding
# that a difference is bigger than that.
#
# THIS IS THE PRIMARY OUTPUT OF THE WHOLE PIPELINE, and it exists because of one
# sentence from the captain: *"I just want more confidence that changes we are
# making are improving results."* A board that prints "contradictions: 3" after
# a change and "contradictions: 5" before it looks like evidence and is not.
# Every turn in both boards is model output. Run the SAME code over the SAME
# world with the SAME script twice and the counts move on their own.
#
# HOW FAR THEY MOVE IS MEASURED, NOT ASSUMED. Twelve whole-run transcripts from
# the four-arm lab sweep -- three repetitions each of one eleven-turn script
# against one seeded world, identical in every respect but the sampling --
# raise these `third_person_protagonist` counts:
#
#     mistral   3, 3, 6        gemini   3, 0, 0
#     kimi      6, 3, 2        minimax  2, 1, 0
#
# Every one of those arms is one unchanged configuration. The within-arm spread
# is 3 to 6 flags on ELEVEN turns; the between-arm difference anybody would want
# to claim is about the same size. That is the finding this module exists to
# report, and it is why nothing here reports a delta without one.
#
# THE RULE, and why it is this rule.
#
#   REAL          the two sets of runs are separated by an exact rank test at
#                 ALPHA, and the difference is in the direction claimed.
#   NOISE         not separated, AND the difference is no larger than the
#                 spread one unchanged configuration already produced.
#   INCONCLUSIVE  everything else: too few runs for the test to be able to
#                 reach ALPHA at all, a check that was unavailable on either
#                 side, or a difference too large to call noise and too small
#                 to call real.
#
# IN PRACTICE, AT THESE SAMPLE SIZES, INCONCLUSIVE MEANS "NOT ENOUGH RUNS", and
# that is worth knowing before reading one. The third branch -- a difference
# wider than the band but not separated -- is nearly unreachable at five runs a
# side, because two sets tight enough to have a narrow band are also tight
# enough for the rank test to separate them. So an INCONCLUSIVE on a check that
# had runs on both sides is unusual and worth looking at by hand.
#
# WHY A RANK TEST AND NOT A t-TEST. Flag counts per run are small integers,
# frequently zero, and nothing about them is normal. A permutation test on the
# ranks assumes none of that: it asks how many of the ways these runs could have
# been split between "before" and "after" produce a separation at least this
# large.
#
# AND WHY FOUR RUNS A SIDE IS THE FLOOR -- it is arithmetic, not a preference.
# The test is two-sided, so the smallest p it can possibly return is 2 divided
# by the number of arrangements:
#
#     3 a side    20 arrangements    smallest p = 0.100   ABOVE ALPHA: no
#                                                          verdict is reachable
#     4 a side    70 arrangements    smallest p = 0.029
#     5 a side   252 arrangements    smallest p = 0.008
#
# At three a side a perfect separation -- every single run of one set worse than
# every single run of the other -- still cannot clear 0.05. Reporting anything
# but INCONCLUSIVE there would be reporting the sample size as a result.
#
# WHAT REDUCES THE FLOOR, in the order they are worth reaching for: more turns
# per run (a bigger denominator per rep, and the cheapest of these), more reps,
# and pinning the model so rotation cannot answer a turn from somewhere else
# (`OPENROUTER_MODEL`, which the runner sets). Temperature is deliberately NOT
# on that list: the eval has to measure the game the player gets, and a sweep
# run at a temperature the app never uses is a measurement of a different app.
module Eval::Noise
  extend self

  # The significance level. Ordinary, and stated rather than tuned: moving it
  # after seeing a result is how a measurement becomes an argument.
  ALPHA = 0.05

  # FEWER THAN THIS MANY RUNS A SIDE AND NO VERDICT IS GIVEN. At 4 v 4 the
  # smallest attainable p is 1/70 = 0.014, which is under ALPHA with room to
  # spare; at 3 v 3 it is exactly 0.05 and a pass would mean nothing.
  MIN_RUNS = 4

  # Above this many arrangements the exact enumeration is abandoned for the
  # normal approximation. 5 v 5 is 252 and 9 v 9 is 48,620, so every default
  # sweep is exact.
  EXACT_LIMIT = 100_000

  # ONE CHECK'S SPREAD ACROSS RUNS THAT SHOULD HAVE AGREED.
  Spread = Data.define(:code, :values) do
    def runs = values.size
    def min = values.min || 0
    def max = values.max || 0
    def median = Eval.median(values)
    def range = max - min
    def to_h = { runs:, min:, max:, median:, range: }
  end

  def spread(code, values) = Spread.new(code: code, values: Array(values).compact)

  # THE VERDICT ON ONE CHECK BETWEEN TWO SETS OF RUNS.
  #
  # `band` is the noise floor this comparison is judged against: the wider of
  # the two sides' own observed ranges. It is the honest one to use -- both
  # sides are unchanged configurations internally, so whatever either of them
  # produced on its own is a difference that needs no explanation.
  Verdict = Data.define(:code, :before, :after, :p_value, :exact, :outcome, :band) do
    def delta = after.median - before.median
    def improved? = delta.negative?
    def real? = outcome == :real
    def noise? = outcome == :noise
    def inconclusive? = outcome == :inconclusive

    def headline
      case outcome
      when :real then "REAL (p=#{format("%.4f", p_value)}#{exact ? "" : ", approximate"})"
      when :noise then format("NOISE (inside the %.3f the unchanged runs already spanned)", band)
      else "INCONCLUSIVE"
      end
    end

    def to_h = { code:, before: before.to_h, after: after.to_h, delta: delta.round(4),
                 p_value: p_value&.round(6), exact:, outcome:, band: }
  end

  # `before` and `after` are one number per run -- a rate, or a count over a
  # fixed script. Rates are what the board passes, so a run that failed a turn
  # and produced fewer passages is compared on the same footing as one that did
  # not.
  def compare(code, before, after)
    left = Spread.new(code: code, values: Array(before).compact.map(&:to_f))
    right = Spread.new(code: code, values: Array(after).compact.map(&:to_f))
    band = [ left.range, right.range ].max

    if left.runs < MIN_RUNS || right.runs < MIN_RUNS
      return Verdict.new(code:, before: left, after: right, p_value: nil, exact: false,
                         outcome: :inconclusive, band: band)
    end

    p_value, exact = significance(left.values, right.values)
    outcome =
      if p_value <= ALPHA then :real
      elsif (right.median - left.median).abs <= band then :noise
      else :inconclusive
      end

    Verdict.new(code:, before: left, after: right, p_value:, exact:, outcome:, band:)
  end

  # THE TWO-SIDED PERMUTATION TEST ON RANK SUMS, exact where the arrangements
  # can be counted and normal-approximated where they cannot. Ties are handled
  # by construction: the pooled values are ranked once, midranks and all, and
  # every split of THOSE ranks is enumerated -- so a set of runs that all
  # flagged zero returns p = 1, which is the right answer and the one a
  # closed-form U test with no tie correction gets wrong.
  def significance(left, right)
    ranks = midranks(left + right)
    a = ranks.first(left.size)
    observed = a.sum

    arrangements = combinations(ranks.size, left.size)
    return [ approximate(left, right, ranks), false ] if arrangements > EXACT_LIMIT

    centre = ranks.sum * left.size.fdiv(ranks.size)
    extreme = 0
    ranks.combination(left.size) { |pick| extreme += 1 if (pick.sum - centre).abs >= (observed - centre).abs - 1e-9 }

    [ extreme.fdiv(arrangements), true ]
  end

  private

  # Ranks with ties averaged, which is what makes the enumeration above a test
  # about ordering rather than about the values themselves.
  def midranks(values)
    order = values.each_with_index.sort_by { |value, index| [ value, index ] }
    ranks = Array.new(values.size)

    position = 0
    while position < order.size
      last = position
      last += 1 while last + 1 < order.size && order[last + 1][0] == order[position][0]
      average = ((position + 1) + (last + 1)) / 2.0
      (position..last).each { |slot| ranks[order[slot][1]] = average }
      position = last + 1
    end

    ranks
  end

  def combinations(total, pick)
    (0...pick).reduce(1) { |product, step| product * (total - step) / (step + 1) }
  end

  # The normal approximation, with the tie correction, for sets too large to
  # enumerate. Reported as `exact: false` so a reader knows which they got.
  def approximate(left, right, ranks)
    n1 = left.size
    n2 = right.size
    total = n1 + n2
    mean = n1 * (total + 1) / 2.0
    ties = ranks.tally.values.sum { |count| (count**3) - count }
    variance = (n1 * n2 / 12.0) * ((total + 1) - ties.fdiv(total * (total - 1)))
    return 1.0 if variance <= 0

    z = (ranks.first(n1).sum - mean).abs / Math.sqrt(variance)
    2 * (1 - phi(z))
  end

  def phi(z)
    0.5 * (1 + Math.erf(z / Math.sqrt(2)))
  end
end
