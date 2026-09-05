# TWO PROMPT BENCH RUNS, WITH A VERDICT PER CHECK: REAL, NOISE or INCONCLUSIVE.
#
# The same rule as everything else in this module -- `Eval::Noise`, a two-sided
# exact rank test at ALPHA with the noise floor taken as the wider of the two
# sides' own observed ranges. Four repetitions a side is the arithmetic floor
# for any verdict, which at three a side means INCONCLUSIVE however clean the
# separation looks.
#
# WHAT IT IS FOR, and it is the whole reason this bench exists: a prompt-shaped
# change is judged HERE first and confirmed by `rake eval:run` after. The two
# sets differ in exactly one of two ways, and the printer says which:
#
#   TWO PROMPT VERSIONS ON ONE MODEL -- the ordinary before/after of a prompt
#   change. Same arm both sides, same `corpus_digest`, different
#   `prompt_digest`. This is what `ta-take-drop-narration` will be judged with.
#
#   TWO MODELS ON ONE PROMPT VERSION -- the model comparison, off the stored
#   files alone. Different arms, same `prompt_digest`.
#
# AND THE THIRD SHAPE IS THE ONE TO REFUSE TO READ: different models AND a
# different prompt. Whatever moved cannot be attributed to either, and a table
# of verdicts is the easiest place in the world to forget that -- so it is said
# loudly above the verdicts rather than left to be worked out. The digests are
# what make that sayable at all; see `Eval::Prompt::Version`.
#
# A DIFFERENT CORPUS IS WORSE THAN EITHER, and gets the same treatment: two sets
# scored on different cases are not comparable and the difference between them
# is a difference between two files.
#
# PER ARM, NEVER POOLED. Two models are two measurements.
class Eval::Prompt::Comparison
  Row = Data.define(:arm, :metric, :verdict) do
    def neutral? = Eval::Prompt::Result::NEUTRAL.include?(metric)

    def improved?
      Eval::Prompt::Result.lower_is_better.include?(metric) ? verdict.delta.negative? : verdict.delta.positive?
    end

    def direction
      # RICHNESS AND SPEND HAVE NO BETTER DIRECTION, and saying so is the point
      # of printing them: prose that says less cannot contradict the records, so
      # a fall here beside a fall in every rate is a prompt that bought its
      # numbers with blander prose. See `Eval::Richness`.
      return "reported" if neutral?
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

  def cross_prompt?
    before.prompt_digest.present? && after.prompt_digest.present? &&
      before.prompt_digest != after.prompt_digest
  end

  def comparable_corpus?
    before.corpus_digest.nil? || after.corpus_digest.nil? || before.corpus_digest == after.corpus_digest
  end

  def verdicts(arm, against: arm)
    Eval::Prompt::Result.metrics.keys.map do |metric|
      Row.new(arm: arm, metric: metric,
              verdict: Eval::Noise.compare(metric, before.values(metric, arm: against),
                                           after.values(metric, arm: arm)))
    end
  end

  def print
    say Eval::Prompt::Report::RULE
    say "PROMPT BENCH: #{before.name} -> #{after.name}"
    say "Exact rank test at p <= #{Eval::Noise::ALPHA}, #{Eval::Noise::MIN_RUNS} repetitions a side minimum."
    say Eval::Prompt::Report::RULE
    provenance(before)
    provenance(after)
    say "Latencies are WARM-CACHE figures -- each arm's first call is timed apart and excluded."

    warnings

    pairs.each do |against, arm|
      say
      say(against == arm ? "MODEL  #{arm}" : "MODEL  #{against} (before)  ->  #{arm} (after)")
      verdicts(arm, against: against).each do |row|
        verdict = row.verdict
        say format("  %-26s %s -> %s  %-9s %s", row.metric,
                   figure(row.metric, verdict.before.median), figure(row.metric, verdict.after.median),
                   row.direction, verdict.headline)
      end
    end

    closing
  end

  private

  def provenance(set)
    say "#{set.name}: #{set.arms.join(", ")} | corpus #{set.corpus_digest || "unrecorded"} | " \
        "prompt #{set.prompt_digest || "unrecorded"} | #{set.reps} reps"
  end

  def warnings
    unless comparable_corpus?
      say
      say "WARNING: THE TWO SETS SCORED DIFFERENT CORPORA (#{before.corpus_digest} vs #{after.corpus_digest})."
      say "Whatever moved below may be the cases moving and not the prompt. Re-run one side."
    end

    if cross_model? && cross_prompt?
      say
      say "WARNING: THE MODEL AND THE PROMPT BOTH CHANGED. Nothing below can be attributed to"
      say "either one. Re-run one side so that exactly one of them moves."
    elsif cross_model?
      say
      say "THIS IS A MODEL COMPARISON on one prompt version, not a before/after of one prompt."
    elsif cross_prompt?
      say
      say "This is a PROMPT comparison on one model: #{before.prompt_digest} -> #{after.prompt_digest}."
    else
      say
      say "NOTE: the two sets record the SAME prompt digest, so this is the same prompt measured"
      say "twice -- the null check. Everything below should read NOISE."
    end

    dropped = (before.arms | after.arms) - pairs.flatten.uniq
    say "Models on only one side and therefore not compared: #{dropped.join(", ")}." if dropped.any?
  end

  def figure(metric, value)
    return format("%.2fs", value) if Eval::Prompt::Result::SECONDS.include?(metric)
    return format("%d", value) if Eval::Prompt::Result::COUNTED.include?(metric)

    format("%.3f", value)
  end

  def closing
    say
    say "A REAL verdict on a CHECK is what means a prompt change worked. Read `commitments`"
    say "beside it: a fall in every rate with a fall in that is prose that says less, which is"
    say "the one way to improve these numbers without improving the game (Eval::Richness)."
    say "Everything INCONCLUSIVE at these sample sizes means: not enough repetitions."
    say "Confirm a REAL verdict with `rake eval:run` before believing it."
    say Eval::Prompt::Report::RULE
  end

  def say(line = "") = io&.puts(line)
end
