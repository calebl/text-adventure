# THE BOARD, AND THE DISCIPLINE IS `EVALUATION.md`'S.
#
# NO SINGLE NUMBER, AND EVERY RATE WITH ITS BAND. This is prose at the app's own
# temperature: the same case, asked twice, comes back differently, and a
# difference smaller than the band the repetitions already span is nothing. So
# every figure here is min..max with the median in the middle, per model, never
# pooled -- and REAL / NOISE is `Eval::Noise`'s to say, two sets at a time,
# which is `rake eval:prompt_compare`.
#
# WHAT IT PRINTS, and why each is apart from the others:
#
#   THE CHECKS            one rate per check, over the cases that check can
#                         actually be judged on. `Story::Scoreboard`'s order,
#                         which is the trust ordering: what the records prove
#                         first.
#   THE UNAVAILABLE ONES  named, with the reason, UNDER the rates and never
#                         beside them. Four checks a single turn cannot answer,
#                         and a zero for any of them would be the most
#                         dangerous number this instrument could print.
#   TUNING AND HELD OUT   apart and labelled, exactly as `Eval::Board` prints
#                         them. This bench exists so a prompt can be tuned
#                         against a measurement, and a prompt tuned against
#                         every case in the file is a prompt fitted to the file.
#   RICHNESS              beside the rates and NEVER folded in. Prose that says
#                         less cannot contradict the records; see
#                         `Eval::Richness`.
#   WHAT PROSE CANNOT SHOW  refusals, omitted fields, fields cut off at their
#                         cap, failures by class, latency, tokens, spend.
#   THE FLAGGED PASSAGES  with what was typed and the offending sentence, on
#                         `rake game:score`'s rule: the captain's attention goes
#                         only to what a check caught.
class Eval::Prompt::Report
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
    say "THE PROMPT BENCH -- #{result.corpus_size} single-turn cases, #{result.reps} repetitions, " \
        "#{result.arms.size} model#{"s" unless result.arms.one?}"
    say "corpus #{result.corpus_digest}   prompt #{result.prompt_digest}   " \
        "instructions #{result.instructions_digest}"
    say "Every rate is min..max over the repetitions with the median in the middle. A"
    say "difference smaller than that band is not a difference -- see EVALUATION.md."
    say "THE LATENCIES ARE WARM-CACHE FIGURES: each arm's first call is timed separately"
    say "and excluded."
    unless result.prompt_stable
      say
      say "WARNING: THE DESIGNATED CASE OF SOME SHAPE SENT TWO DIFFERENT PROMPTS IN THIS RUN."
      say "The facts a case is built on are supposed to be constant. Until that is explained,"
      say "every figure below is measuring something that moved. See Eval::Prompt::Version."
    end
    say RULE
  end

  def arm_board(arm, sample:)
    passes = result.for_arm(arm)
    say
    say "MODEL  #{arm}   (#{passes.size} rep#{"s" unless passes.size == 1}, " \
        "#{passes.sum(&:scanned)} passages)"
    say

    checks(arm)
    unavailable
    say
    by_world(arm)
    say
    richness(arm)
    say
    operations(arm, passes)
    say
    flagged(arm, sample: sample)
  end

  def checks(arm)
    say "  THE CHECKS -- flagged over the cases each one can be judged on"
    Eval::Prompt.checks.each do |code|
      judgeable = result.for_arm(arm).map { |pass| pass.judgeable[code.to_s].to_i }
      if judgeable.sum.zero?
        say format("  %-26s %s   %s", code, "unavailable in this corpus",
                   "no case carries the records this check reads")
        next
      end

      spread = result.spread(code, arm: arm)
      flagged = result.for_arm(arm).map { |pass| pass.flagged[code.to_s].to_i }
      say format("  %-26s %s   %d..%d of %d   %s", code, band(code, spread),
                 flagged.min, flagged.max, Eval.median(judgeable).round,
                 Story::Scoreboard::CHECKS.fetch(code))
    end
  end

  def unavailable
    say
    say "  UNAVAILABLE TO A SINGLE TURN -- reported, never scored as clean"
    Eval::Prompt::UNAVAILABLE_TO_A_CASE.each do |code, reason|
      say format("  %-26s %s", code, reason)
    end
  end

  # TUNING AND HELD OUT, APART AND LABELLED -- `Eval::Board`'s rule, and it
  # matters more here than there. This bench exists so a prompt can be tuned
  # against a measurement; a prompt tuned against every case in the file is a
  # prompt fitted to the file, and `The Salt Assizes` is the world that says so.
  # Pooled over the repetitions, because a per-world rate split four ways is a
  # handful of cases and a band nobody can read.
  def by_world(arm)
    rows = result.for_arm(arm).flat_map(&:rows)
    say "  BY WORLD -- flagged of judgeable, pooled over the repetitions"
    rows.group_by { |row| row["story"] }.sort.each do |story, scoped|
      scorer = Eval::Prompt::Scorer.new(scoped)
      counts = Eval::Prompt.checks.filter_map { |code|
        flagged = scorer.flagged_for(code).size
        next if flagged.zero?

        "#{code} #{flagged}/#{scorer.judgeable_for(code)}"
      }
      say format("    %-24s%-12s %d passages   %s", story,
                 Eval::Prompt.held_out?(story) ? " [HELD OUT]" : "",
                 scorer.scanned, counts.any? ? counts.join(", ") : "nothing flagged")
    end
  end

  # THE CHECK ON THE CHECKS. Never folded into anything above it, and printed
  # here rather than at the end so it is read WITH the rates: a prompt change
  # that lowered every rate and halved this bought its numbers with blander
  # prose.
  def richness(arm)
    say "  RICHNESS -- what the prose COMMITTED TO, and it is never folded into the rates"
    %i[words commitments].each do |figure|
      spread = result.spread(figure, arm: arm)
      say format("  %-26s %s   %s", figure, band(figure, spread),
                 Eval::Prompt::Result::RUN_METRICS.fetch(figure))
    end
  end

  def operations(arm, passes)
    say "  WHAT A STORED PASSAGE CANNOT SHOW"
    %i[refusals failures omitted_fields cap_hits latency_median latency_p95 output_tokens].each do |figure|
      spread = result.spread(figure, arm: arm)
      say format("  %-26s %s   %s", figure, band(figure, spread),
                 Eval::Prompt::Result::RUN_METRICS.fetch(figure))
    end

    parsed = Eval::Classifier::Arm.parse(arm)
    input = passes.sum(&:input_tokens)
    output = passes.sum(&:output_tokens)
    say format("  %-26s %s", "spend",
               parsed.local? ? "nothing -- a local model on the captain's own hardware" :
                 format("$%.4f over %d calls (%s in / %s out)",
                        parsed.price.of(input, output), passes.sum { |pass| pass.rows.size },
                        input.to_fs(:delimited), output.to_fs(:delimited)))

    cold = result.warmup(arm)
    if cold
      say format("  %-26s %s   %s", "first call",
                 cold["seconds"] ? format("%.2fs", cold["seconds"]) : "failed",
                 "EXCLUDED from the figures above, so an outlier shows as one")
    end

    extra = passes.sum(&:extra_calls)
    say format("  %-26s %d   %s", "EXTRA CALLS", extra,
               "a case bought a second model call -- see Eval::Prompt::Corpus") if extra.positive?

    rotations = passes.sum(&:rotations)
    say format("  %-26s %d   %s", "ROTATED", rotations,
               "THE PINNING FAILED -- another model answered and this arm must not be credited") if rotations.positive?

    result.failures_by_class(arm).each { |klass, count| say format("      %-42s %d", klass, count) }
  end

  # THE PASSAGES A CHECK CAUGHT, grouped by case, so a case that failed in every
  # repetition is one entry saying so rather than four. The held-out world's are
  # marked, because a flag there is the one worth acting on.
  def flagged(arm, sample:)
    scorer = Eval::Prompt::Scorer.new(result.for_arm(arm).flat_map(&:rows))
    found = scorer.flags
    return say "  NOTHING FLAGGED. Every passage cleared every check this corpus can run." if found.empty?

    grouped = found.group_by { |flag| [ flag.scene.id, flag.code ] }
                   .sort_by { |(id, code), hits| [ -hits.size, code.to_s, id ] }

    say "  FLAGGED -- #{grouped.size} distinct (case, check) pairs, #{found.size} readings" \
        "#{" (first #{sample})" if grouped.size > sample}"
    grouped.first(sample).each do |(id, code), hits|
      first = hits.first
      say format("    %-30s %-24s x%d%s", id, code, hits.size, first.scene.held_out? ? "   [HELD OUT]" : "")
      say "      typed:   #{first.scene.typed.inspect}"
      say "      says:    #{first.evidence_line.to_s.truncate(200)}"
    end
  end

  def band(figure, spread)
    if Eval::Prompt::Result::COUNTED.include?(figure)
      return format("%8d..%-8d (median %s)", spread.min.round, spread.max.round, Eval.count(spread.median))
    end
    if Eval::Prompt::Result::SECONDS.include?(figure)
      return format("%8s..%-8s (median %7s)", format("%.2fs", spread.min), format("%.2fs", spread.max),
                    format("%.2fs", spread.median))
    end

    format("%.3f..%.3f (median %.3f)", spread.min, spread.max, spread.median)
  end

  def closing
    say
    say RULE
    say "Judge a prompt change against this with `rake eval:prompt_compare BEFORE= AFTER=`."
    say "Four repetitions a side is the arithmetic floor for a verdict -- Eval::Noise::MIN_RUNS."
    say "And confirm it with `rake eval:run`: one turn cannot see pacing or a world in motion."
    say RULE
  end

  def say(line = "") = io&.puts(line)
end
