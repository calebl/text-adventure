# TWO BENCH RUNS, WITH A VERDICT PER FIGURE: REAL, NOISE or INCONCLUSIVE.
#
# The same rule as the prose loop, out of the same module -- `Eval::Noise`, a
# two-sided exact rank test at ALPHA with the noise floor taken as the wider of
# the two sides' own observed ranges. Nothing is re-derived here and nothing is
# softened: four repetitions a side is the arithmetic floor for any verdict
# (`Eval::Noise::MIN_RUNS`), which at three a side means INCONCLUSIVE however
# clean the separation looks.
#
# WHY IT IS A SEPARATE COMMAND FROM `rake eval:compare`, stated so nobody reads
# it as duplication. `Eval::Comparison` compares `Eval::RunSet`s -- one number
# per generated RUN, over checks from `Story::Scoreboard::CHECKS`, with a
# held-out world printed apart. A classifier set has none of those: its unit is
# a repetition of a fixed corpus, its figures are `Eval::Classifier::Result::METRICS`,
# and there is no held-out half because a labelled line is not prose anybody
# tuned a check on. Making one of these masquerade as the other would mean
# writing `Eval::RunScore` rows that describe nothing.
#
# PER ARM, NEVER POOLED. Two models are two measurements.
#
# AND IT COMPARES ACROSS MODELS, which is the captain's instruction of
# 2026-09-04 and the reason a bench set records which model produced it:
# *"comparing model A's set against model B's set must work from the stored
# scores alone."* So the pairing is:
#
#   * models on BOTH sides are compared with themselves -- the ordinary
#     before/after of a prompt change;
#   * with nothing in common and ONE model a side, the two are paired and the
#     board says loudly that it is comparing two different models rather than
#     two versions of one;
#   * with nothing in common and several models a side it refuses and names
#     `BEFORE_MODEL=` / `AFTER_MODEL=`, because guessing which of four to pair
#     with which is how a model gets credited with another model's numbers.
#
# `BEFORE_MODEL=` / `AFTER_MODEL=` force one pair whatever the sets hold, which
# is also how one arm of a two-model set is compared against one arm of another.
#
# THE CORPUS DIGEST IS CHECKED, not assumed. Two sets scored on different
# corpora are not comparable and the difference between them is a difference
# between two files -- so a mismatch is printed as a warning above the verdicts
# rather than left for somebody to work out.
#
# AND SO IS THE CONCURRENCY, with a sharper consequence. A set taken with eight
# calls in flight and one taken serially are fully comparable on six of the
# eight figures and NOT comparable on the two latencies, because a wall clock
# measured against a queueing provider is partly the queue. So a mismatch is a
# banner AND the two latency verdicts are dropped entirely -- see
# `SUPPRESSED_BY_CONCURRENCY`. The checked-in baselines under `db/eval` were all
# taken serially, which is exactly the comparison this guard exists for.
class Eval::Classifier::Comparison
  Row = Data.define(:arm, :metric, :verdict) do
    # WHICH WAY IS BETTER. `Eval::Noise::Verdict#improved?` reads a negative
    # delta as an improvement, which is right for a defect count and backwards
    # for an accuracy -- so the direction is asked of the metric and not of the
    # verdict.
    def improved?
      Eval::Classifier::Result::LOWER_IS_BETTER.include?(metric) ? verdict.delta.negative? : verdict.delta.positive?
    end

    def direction
      return "unchanged" if verdict.delta.zero?

      improved? ? "BETTER" : "WORSE"
    end
  end

  class Unpairable < StandardError; end

  attr_reader :before, :after, :before_model, :after_model, :io

  def initialize(before, after, before_model: nil, after_model: nil, io: $stdout)
    @before = before
    @after = after
    @before_model = before_model
    @after_model = after_model
    @io = io
  end

  def arms = pairs.map(&:last)

  # WHAT IS COMPARED WITH WHAT: a list of [before model, after model].
  def pairs
    return [ [ before_model, after_model ] ] if before_model && after_model

    shared = before.arms & after.arms
    return shared.map { |arm| [ arm, arm ] } if shared.any?
    return [ [ before.arms.sole, after.arms.sole ] ] if before.arms.one? && after.arms.one?

    raise Unpairable, "#{before.name} measured #{before.arms.join(", ")} and #{after.name} measured " \
                      "#{after.arms.join(", ")}; nothing is in common and there is more than one a side. " \
                      "Name the pair: BEFORE_MODEL=<model> AFTER_MODEL=<model>."
  end

  def cross_model? = pairs.any? { |left, right| left != right }

  def comparable_corpus?
    before.corpus_digest.nil? || after.corpus_digest.nil? || before.corpus_digest == after.corpus_digest
  end

  # TWO SETS TAKEN WITH DIFFERENT NUMBERS OF CALLS IN FLIGHT. Not a reason to
  # refuse the comparison -- six of the eight figures are unaffected, measured --
  # but the whole reason for the two that are.
  def comparable_latency? = before.concurrency == after.concurrency

  # THE TWO FIGURES CONCURRENCY CAN MOVE, AND THE ONLY TWO. A latency is a wall
  # clock, and past the provider's own ceiling a wall clock is queueing time
  # rather than model speed: +4% at eight calls in flight and +169% at
  # thirty-two, on the same model on the same day. So a serial BEFORE against a
  # concurrent AFTER would hand back a REAL verdict on `latency_median` that is
  # a fact about the harness and nothing about the classifier -- which is the
  # one thing this class exists to prevent. Suppressed rather than flagged,
  # because a printed number with a caveat above it gets quoted without the
  # caveat.
  SUPPRESSED_BY_CONCURRENCY = %i[latency_median latency_p95].freeze

  def judged_metrics
    keys = Eval::Classifier::Result::METRICS.keys
    comparable_latency? ? keys : keys - SUPPRESSED_BY_CONCURRENCY
  end

  def verdicts(arm, against: arm)
    judged_metrics.map do |metric|
      Row.new(arm: arm, metric: metric,
              verdict: Eval::Noise.compare(metric, before.values(metric, arm: against),
                                           after.values(metric, arm: arm)))
    end
  end

  def print
    say Eval::Classifier::Report::RULE
    say "CLASSIFIER BENCH: #{before.name} -> #{after.name}"
    say "Exact rank test at p <= #{Eval::Noise::ALPHA}, #{Eval::Noise::MIN_RUNS} repetitions a side minimum."
    say Eval::Classifier::Report::RULE
    say "#{before.name} measured #{before.arms.join(", ")}#{" on corpus #{before.corpus_digest}" if before.corpus_digest}"
    say "#{after.name} measured #{after.arms.join(", ")}#{" on corpus #{after.corpus_digest}" if after.corpus_digest}"
    say "Latencies are WARM-CACHE figures -- each arm's first call is timed apart and excluded -- " \
        "at #{before.concurrency} and #{after.concurrency} calls in flight respectively."

    unless comparable_latency?
      say
      say "WARNING: THE TWO SETS WERE TAKEN AT DIFFERENT CONCURRENCIES " \
          "(#{before.concurrency} vs #{after.concurrency} calls in flight)."
      say "#{SUPPRESSED_BY_CONCURRENCY.join(" and ")} ARE NOT REPORTED BELOW: a latency taken with more"
      say "calls in flight is partly the provider's queue, so a verdict on it would be a fact about"
      say "the harness. Everything else below is unaffected -- the answers themselves were measured"
      say "identical serial against eight in flight. Re-run one side at the other's concurrency to"
      say "compare speed. See EVALUATION.md -> Concurrency."
    end

    unless comparable_corpus?
      say
      say "WARNING: THE TWO SETS SCORED DIFFERENT CORPORA (#{before.corpus_digest} vs #{after.corpus_digest})."
      say "Whatever moved below may be the labelled lines moving and not the classifier. Re-run one side."
    end

    if cross_model?
      say
      say "THIS IS A MODEL COMPARISON, not a before/after of one model."
      say pairing_note
    end

    dropped = (before.arms | after.arms) - pairs.flatten.uniq
    say "Models on only one side and therefore not compared: #{dropped.join(", ")}." if dropped.any?

    pairs.each do |against, arm|
      say
      say(against == arm ? "MODEL  #{arm}" : "MODEL  #{against} (before)  ->  #{arm} (after)")
      verdicts(arm, against: against).each do |row|
        verdict = row.verdict
        say format("  %-20s %s -> %s  %-8s %s", row.metric,
                   figure(row.metric, verdict.before.median), figure(row.metric, verdict.after.median),
                   row.direction, verdict.headline)
      end
      cold(against, arm)
    end

    say
    say "A REAL verdict on `strict_accuracy` is the one that means a prompt change worked,"
    say "or -- across two models -- that one of them reads the player better than the other."
    say "Everything INCONCLUSIVE at these sample sizes means: not enough repetitions."
    say Eval::Classifier::Report::RULE
  end

  private

  # THE COLD START IS REPORTED AND NOT JUDGED. It is one observation per arm per
  # set -- `Eval::Noise` needs `MIN_RUNS` of them to say anything at all -- so a
  # verdict on it would be the sample size talking. It is printed because a
  # model that answers in half a second and takes forty to load is a different
  # proposition from one that does neither.
  def cold(before_arm, after_arm)
    left = before.warmup(before_arm)
    right = after.warmup(after_arm)
    return if left.nil? && right.nil?

    say format("  %-20s %s -> %s  %-8s %s", "first call (cold)",
               left && left["seconds"] ? format("%.2fs", left["seconds"]) : "--",
               right && right["seconds"] ? format("%.2fs", right["seconds"]) : "--",
               "", "one observation an arm; reported, never judged")
  end

  # A count, a number of seconds and a rate are three different things and a
  # comparison that printed them all to three decimals would be lying about two.
  def figure(metric, value)
    return format("%.2fs", value) if Eval::Classifier::Result::SECONDS.include?(metric)
    return format("%d", value) if Eval::Classifier::Result::COUNTED.include?(metric)

    format("%.3f", value)
  end

  # WHY THESE TWO MODELS ARE BEING READ AGAINST EACH OTHER, because a forced
  # pair and a pair that fell out of the sets are different facts about the
  # comparison.
  def pairing_note
    return "The pair was named, so one arm of each side is being read against the other." if before_model && after_model

    "The two sets have no model in common, so each side's own model is being read against the other's."
  end

  def say(line = "") = io&.puts(line)
end
