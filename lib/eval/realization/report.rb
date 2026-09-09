# THE BOARD, AND THE DISCIPLINE IS `EVALUATION.md`'S.
#
# NO SINGLE NUMBER, AND EVERY RATE WITH ITS BAND. A realization is model output
# at the app's own temperature: the same stub, asked twice, comes back with
# different rooms, so a difference smaller than the band the repetitions already
# span is nothing. Every figure here is min..max with the median in the middle,
# per model, never pooled -- and REAL / NOISE is `Eval::Noise`'s to say, two
# sets at a time, which is `rake eval:realization_compare`.
#
# WHAT IT PRINTS, and why each is apart from the others:
#
#   THE CHECKS            one rate per check, over the opportunities that check
#                         can actually be judged on. In `Scorer::CHECKS` order,
#                         which is the trust ordering: what the records prove
#                         first, `Scorer::KEYWORD_CHECKS` last and labelled.
#   THE UNAVAILABLE ONES  named, with the reason, UNDER the rates and never
#                         beside them -- every question in
#                         `UNAVAILABLE_TO_A_REALIZATION`, because a zero for any
#                         of them would be the most dangerous number this
#                         instrument could print.
#   TUNING AND HELD OUT   apart and labelled, exactly as `Eval::Board` prints
#                         them. This bench exists so a prompt can be tuned
#                         against a measurement, and a prompt tuned against
#                         every case in the file is a prompt fitted to the file.
#   WHAT WAS IN THE ROOM  the counts, beside the rates and NEVER folded in: the
#                         cheapest way to clear every rate above is to write one
#                         exit and nobody. See `Eval::Realization::Scorer`.
#   WHAT AN ANSWER CANNOT SHOW  refusals, omitted fields, fields cut off at
#                         their cap, failures by class, latency, tokens, spend.
#   THE FLAGGED ROOMS     with the name that caused it, on `rake game:score`'s
#                         rule: the captain's attention goes only to what a
#                         check caught.
class Eval::Realization::Report
  DEFAULT_SAMPLE = 12

  RULE = ("-" * 78).freeze

  attr_reader :result, :io

  def initialize(result, io: $stdout)
    @result = result
    @io = io
  end

  def print(sample: DEFAULT_SAMPLE)
    heading
    result.arms.each { |arm| arm_board(arm, sample: sample) }
    closing
  end

  private

  def heading
    say RULE
    say "THE REALIZATION BENCH -- #{result.corpus_size} stubs, #{result.reps} repetitions, " \
        "#{result.arms.size} model#{"s" unless result.arms.one?}"
    say "corpus #{result.corpus_digest}   prompt #{result.prompt_digest}   " \
        "instructions #{result.instructions_digest}"
    say "Every rate is min..max over the repetitions with the median in the middle. A"
    say "difference smaller than that band is not a difference -- see EVALUATION.md."
    say "THE LATENCIES ARE WARM-CACHE FIGURES: each arm's first realization is timed"
    say "separately and excluded."
    unless result.prompt_stable
      say
      say "WARNING: THE DESIGNATED CASE OF SOME SHAPE SENT TWO DIFFERENT PROMPTS IN THIS RUN."
      say "The world a case is staged in is supposed to be constant, and the one part that is"
      say "not -- the engine's own cast roll -- is scrubbed before the digest is taken. So this"
      say "is something else moving, and every figure below is measuring it. See"
      say "Eval::Realization::Version."
    end
    say RULE
  end

  def arm_board(arm, sample:)
    passes = result.for_arm(arm)
    say
    say "MODEL  #{arm}   (#{passes.size} rep#{"s" unless passes.size == 1}, " \
        "#{passes.sum(&:scanned)} rooms)"
    say

    checks(arm)
    unavailable
    say
    by_world(arm)
    say
    reported(arm)
    say
    operations(arm, passes)
    say
    flagged(arm, sample: sample)
  end

  def checks(arm)
    say "  THE CHECKS -- flagged over the opportunities each one can be judged on"
    Eval::Realization.checks.each do |code|
      judgeable = result.for_arm(arm).map { |pass| pass.judgeable[code.to_s].to_i }
      # THE KEYWORD LABEL IS PRINTED WHETHER OR NOT THE CHECK FIRED, because it
      # is a fact about what the check CAN see rather than about this run.
      keyword = Eval::Realization::Scorer::KEYWORD_CHECKS.include?(code) ? "  [KEYWORD]" : ""

      if judgeable.sum.zero?
        say format("  %-28s %s   %s%s", code, "unavailable in this corpus",
                   "nothing in this run gave the check anything to read", keyword)
      else
        spread = result.spread(code, arm: arm)
        flagged = result.for_arm(arm).map { |pass| pass.flagged[code.to_s].to_i }
        say format("  %-28s %s   %d..%d of %d%s", code, band(code, spread),
                   flagged.min, flagged.max, Eval.median(judgeable).round, keyword)
      end
      say format("  %-28s   %s", "", Eval::Realization::Scorer::CHECKS.fetch(code))
    end
  end

  def unavailable
    say
    say "  UNAVAILABLE TO THIS BENCH -- reported, never scored as clean"
    Eval::Realization::UNAVAILABLE_TO_A_REALIZATION.each do |code, reason|
      say format("  %-28s %s", code, reason)
    end
  end

  # TUNING AND HELD OUT, APART AND LABELLED -- `Eval::Board`'s rule. Pooled over
  # the repetitions, because a per-world rate split four ways is a handful of
  # rooms and a band nobody can read.
  def by_world(arm)
    rows = result.for_arm(arm).flat_map(&:rows)
    say "  BY WORLD -- flagged of judgeable, pooled over the repetitions"
    rows.group_by { |row| row["story"] }.sort.each do |story, scoped|
      scorer = Eval::Realization::Scorer.new(scoped)
      counts = Eval::Realization.checks.filter_map { |code|
        flagged = scorer.flagged_for(code).size
        next if flagged.zero?

        "#{code} #{flagged}/#{scorer.judgeable_for(code)}"
      }
      say format("    %-26s%-12s %d rooms   %s", story,
                 Eval::Realization.held_out?(story) ? " [HELD OUT]" : "",
                 scorer.scanned, counts.any? ? counts.join(", ") : "nothing flagged")
    end
  end

  # THE CHECK ON THE CHECKS. Never folded into anything above it, and printed
  # here rather than at the end so it is read WITH the rates: a prompt change
  # that lowered every rate and halved these built emptier rooms.
  def reported(arm)
    say "  WHAT WAS ACTUALLY IN THE ROOM -- never folded into the rates above"
    Eval::Realization::Result::REPORTED_METRICS.each_key do |figure|
      spread = result.spread(figure, arm: arm)
      # NO RUNS AT ALL IS NOT NOUGHT. A figure a set never recorded -- a kept
      # summary written before it existed -- has every value nil, and
      # `Eval::Noise.spread` compacts those, so a band printed off it would read
      # 0.000 for a question the set was never asked. `#checks` above says
      # `unavailable` for the same state and this is the same rule one section
      # down.
      if spread.runs.zero?
        say format("  %-28s %s   %s", figure, "unavailable in this set",
                   Eval::Realization::Result::REPORTED_METRICS.fetch(figure))
        next
      end

      say format("  %-28s %s   %s", figure, band(figure, spread),
                 Eval::Realization::Result::REPORTED_METRICS.fetch(figure))
    end
  end

  def operations(arm, passes)
    say "  WHAT A STORED ANSWER CANNOT SHOW"
    say "  (the first three are the schema-validity figures: a field absent, a field cut off,"
    say "   and a call that did not answer at all)"
    Eval::Realization::Result::RUN_METRICS.each_key do |figure|
      spread = result.spread(figure, arm: arm)
      say format("  %-28s %s   %s", figure, band(figure, spread),
                 Eval::Realization::Result::RUN_METRICS.fetch(figure))
    end

    parsed = Eval::Classifier::Arm.parse(arm)
    input = passes.sum(&:input_tokens)
    output = passes.sum(&:output_tokens)
    say format("  %-28s %s", "spend",
               parsed.local? ? "nothing -- a local model on the captain's own hardware" :
                 format("$%.4f over %d realizations (%s in / %s out)",
                        parsed.price.of(input, output), passes.sum { |pass| pass.rows.size },
                        input.to_fs(:delimited), output.to_fs(:delimited)))

    cold = result.warmup(arm)
    if cold
      say format("  %-28s %s   %s", "first realization",
                 cold["seconds"] ? format("%.2fs", cold["seconds"]) : "failed",
                 "EXCLUDED from the figures above, so an outlier shows as one")
    end

    extra = passes.sum(&:extra_calls)
    say format("  %-28s %d   %s", "EXTRA CALLS", extra,
               "a case bought a call beyond the two a realization makes") if extra.positive?

    rotations = passes.sum(&:rotations)
    say format("  %-28s %d   %s", "ROTATED", rotations,
               "THE PINNING FAILED -- another model answered and this arm must not be credited") if rotations.positive?

    result.failures_by_class(arm).each { |klass, count| say format("      %-42s %d", klass, count) }
  end

  # WHAT A CHECK CAUGHT, grouped by case, so a case that failed in every
  # repetition is one entry saying so rather than four. The held-out world's are
  # marked, because a flag there is the one worth acting on.
  def flagged(arm, sample:)
    scorer = Eval::Realization::Scorer.new(result.for_arm(arm).flat_map(&:rows))
    found = scorer.flags
    return say "  NOTHING FLAGGED. Every room cleared every check this corpus can run." if found.empty?

    grouped = found.group_by { |flag| [ flag.id, flag.code ] }
                   .sort_by { |(id, code), hits| [ -hits.size, code.to_s, id.to_s ] }

    say "  FLAGGED -- #{grouped.size} distinct (case, check) pairs, #{found.size} readings" \
        "#{" (first #{sample})" if grouped.size > sample}"
    grouped.first(sample).each do |(id, code), hits|
      first = hits.first
      say format("    %-30s %-28s x%d%s", id, code, hits.size, first.held_out? ? "   [HELD OUT]" : "")
      say "      #{first.evidence.to_s.truncate(200)}"
    end
  end

  def band(figure, spread)
    if Eval::Realization::Result::COUNTED.include?(figure)
      return format("%8d..%-8d (median %s)", spread.min.round, spread.max.round, Eval.count(spread.median))
    end
    if Eval::Realization::Result::SECONDS.include?(figure)
      return format("%8s..%-8s (median %7s)", format("%.2fs", spread.min), format("%.2fs", spread.max),
                    format("%.2fs", spread.median))
    end
    if Eval::Realization::Result::MEANS.include?(figure)
      return format("%8.2f..%-8.2f (median %.2f)", spread.min, spread.max, spread.median)
    end

    format("%.3f..%.3f (median %.3f)", spread.min, spread.max, spread.median)
  end

  def closing
    say
    say RULE
    say "Judge a prompt change against this with `rake eval:realization_compare BEFORE= AFTER=`."
    say "Four repetitions a side is the arithmetic floor for a verdict -- Eval::Noise::MIN_RUNS."
    say "And confirm it with `rake eval:run`: a room measured on its own cannot show what it is"
    say "like to walk into three turns later."
    say RULE
  end

  def say(line = "") = io&.puts(line)
end
