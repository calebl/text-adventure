# THE BOARD, AND THE DISCIPLINE IS `EVALUATION.md`'S.
#
# NO SINGLE NUMBER, AND EVERY RATE WITH ITS BAND. A classifier bench is easier
# to fool yourself with than the prose one, because the answers look
# deterministic -- one word out of six, one name out of a closed enum, at
# `TEMPERATURE = 0.0`. They are not: a provider serves the same prompt from
# different hardware and the same line does not always come back the same way.
# So every figure here is printed as the min, median and max over the
# repetitions, and a difference smaller than that band is nothing.
#
# WHAT IT PRINTS, and why each is a separate figure rather than folded in:
#
#   THE HEADLINE          the whole answer right -- intent AND record -- over the
#                         lines whose English admits one reading. The number a
#                         prompt change has to move.
#   PER INTENT            because the six branches have different consequences:
#                         a wrong `move` walks the player into another room and a
#                         wrong `examine` narrates.
#   THE CONFUSION MATRIX  which intent was answered for which, because "78%
#                         accurate" and "every `other` came back as `examine`"
#                         are the same rate and different bugs.
#   CLOSED-SET MISSES     right branch, wrong record. Counted and LISTED, on the
#                         same rule `Story::Scoreboard` follows: the captain's
#                         attention goes only to what a check caught.
#   `also_named`          precision and recall, because it is a DETECTOR --
#                         PR 102's finding F4 -- and a detector has two ways to
#                         be wrong. A false positive refuses a line that should
#                         have played; a false negative plays half a line.
#   THE OMISSION RATE     how often the required field came back absent or null
#                         in the provider's own JSON. F4's actual worry, read off
#                         `messages.content_raw`.
#   REFUSAL AGREEMENT     whether the line earned the refusal the ruling of
#                         2026-09-04 gives it. The figure that turned the
#                         classifier from a thing that could be a bit wrong into
#                         a thing the player reads.
#   THE OFFLINE FLOOR     the same corpus with no model at all, printed
#                         underneath rather than beside, because it is not a
#                         competing arm -- it is what a classifier call is bought
#                         against.
#
# NOTHING HERE IS AVERAGED ACROSS ARMS. Two models are two measurements, exactly
# as two worlds are in `Eval::Board`, and pooling them would report the
# difference between the models as noise.
class Eval::Classifier::Report
  # How many flagged lines to print in full. The board's job is to put the
  # wrong answers in front of somebody, and a wall of three hundred is not that.
  DEFAULT_SAMPLE = 20

  RULE = ("-" * 78).freeze

  attr_reader :result, :floor, :io

  def initialize(result, floor: nil, io: $stdout)
    @result = result
    @floor = floor
    @io = io
  end

  def print(sample: DEFAULT_SAMPLE)
    heading
    result.arms.each { |arm| arm_board(arm, sample: sample) }
    confusion
    offline_floor
    closing
  end

  # PUBLIC, because `rake eval:classifier_offline` prints this and nothing else:
  # the free half of the instrument is a command of its own, and a rake task
  # reaching into a private method for it would be a seam nobody declared.
  def offline_floor
    return if floor.nil?

    say
    say RULE
    say "THE OFFLINE FLOOR -- the same #{floor.size} lines through the fixed grammar"
    say "(`Playthrough::Mechanics` with `model: false`), no model, no key, no spend. This is"
    say "what a classifier call is bought against, and it is free."
    say
    say format("  right                    %s", ratio(floor.right, floor.size))
    Eval::Classifier::Offline::OUTCOMES.each do |outcome|
      say format("    %-16s %3d   %s", outcome, floor.count(outcome), OUTCOME_MEANINGS.fetch(outcome))
    end
    say
    say "  `refused` is GENEROUS to the grammar: it counts a refusal on a line the label"
    say "  says earns one, and the grammar has no refusal KINDS to check -- its refusals are"
    say "  strings it composes, not `Playthrough::Refusal` objects. So the floor can say"
    say "  whether a line was refused and never which kind. It has no `also_named` at all."
    say
    say "  BY SHAPE"
    floor.by_shape.sort.each do |shape, figures|
      say format("    %-22s %3d/%-4d %.3f", shape, figures[:right], figures[:size], figures[:rate])
    end
  end

  OUTCOME_MEANINGS = {
    resolved: "the grammar produced an answer the label accepts",
    refused: "the grammar refused, and the label says the line earns a refusal",
    wrong: "the grammar produced an answer the label does not accept -- silently",
    over_refused: "the grammar refused a line the label says should have played",
    unparsed: "no verb it knows and no exit by that name, so the whole grammar is printed"
  }.freeze

  private

  def heading
    say RULE
    say "THE CLASSIFIER BENCH -- #{result.corpus_size} labelled lines, #{result.reps} repetitions, " \
        "#{result.arms.size} model#{"s" unless result.arms.one?}"
    say "Every rate is min..max over the repetitions with the median in the middle. A"
    say "difference smaller than that band is not a difference -- see EVALUATION.md."
    say "THE LATENCIES ARE WARM-CACHE FIGURES: every arm's first call is timed separately"
    say "and excluded, because on a local model it is mostly the model being loaded."
    say RULE
  end

  def arm_board(arm, sample:)
    passes = result.for_arm(arm)
    rows = passes.flat_map { |pass| pass.rows.map { |row| row.transform_keys(&:to_s) } }
    say
    parsed = Eval::Classifier::Arm.parse(arm)
    say "MODEL  #{arm}#{"   [LOCAL]" if parsed.local?}   " \
        "(#{passes.size} rep#{"s" unless passes.size == 1}, #{rows.size} readings)"
    say

    Eval::Classifier::Result::METRICS.each do |metric, meaning|
      spread = result.spread(metric, arm: arm)
      say format("  %-20s %s   %s", metric, band(metric, spread), meaning)
    end

    speed_and_flakiness(arm, passes)

    say
    per_intent(rows)
    say
    per_shape(rows)
    say
    also_named(rows)
    say
    refusals(rows)
    say
    misses(rows, sample: sample)
  end

  # A COUNT IS PRINTED AS A COUNT. `closed_set_misses` is a number of lines, not
  # a rate, so formatting it to three decimals would be a lie about what it is.
  def band(metric, spread)
    return format("%3d..%-3d (median %3d)", spread.min, spread.max, spread.median) if counted?(metric)
    return format("%6.2fs..%-6.2fs (median %6.2fs)", spread.min, spread.max, spread.median) if seconds?(metric)

    format("%.3f..%.3f (median %.3f)", spread.min, spread.max, spread.median)
  end

  def counted?(metric) = Eval::Classifier::Result::COUNTED.include?(metric)
  def seconds?(metric) = Eval::Classifier::Result::SECONDS.include?(metric)

  # SPEED AND FLAKINESS TOGETHER, because they are the two ways a model can cost
  # the player a turn and they read differently: a slow arm made them wait, a
  # flaky arm did not answer at all. An arm with failures has its latency
  # measured over the calls that ANSWERED, so the coverage is stated on the same
  # line rather than left to be worked out.
  def speed_and_flakiness(arm, passes)
    parsed = Eval::Classifier::Arm.parse(arm)
    answered = passes.sum { |pass| pass.latencies.size }
    failures = passes.sum(&:failures)
    total = answered + failures

    say format("  %-20s %s", "cost", parsed.local? ?
      "nothing -- a local model on the captain's own hardware, and slow" :
      "#{format("$%.4f", parsed.price.of(Eval::Classifier::PER_CALL[:input] * total,
                                         Eval::Classifier::PER_CALL[:output] * total))} over #{total} calls")
    cold = result.warmup(arm)
    if cold
      say format("  %-20s %s   %s", "first call",
                 cold["seconds"] ? format("%.2fs", cold["seconds"]) : "failed",
                 parsed.local? ? "the model load, EXCLUDED from the figures above -- " \
                                 "kept resident: #{cold["residency"]}" :
                                 "EXCLUDED from the figures above, so an outlier shows as one")
    end
    say format("  %-20s %d of %d   %s", "answered", answered, total,
               failures.zero? ? "every call answered" :
                                "the latency figures above cover these and not the #{failures} that failed")

    if failures.positive?
      say format("  %-20s %d   %s", "FAILED CALLS", failures, "no rotation to hide them: an arm is one model")
      Eval::Classifier::Result.new(corpus_size: 0, arms: [ arm ], reps: passes.size, passes: passes)
                              .failures_by_class(arm).each do |klass, count|
        say format("      %-42s %d", klass, count)
      end
    end

    rotations = passes.sum(&:rotations)
    return if rotations.zero?

    say format("  %-20s %d   %s", "ROTATED", rotations,
               "THE PINNING FAILED -- another model answered and this arm must not be credited")
  end

  def per_intent(rows)
    say "  ACCURACY PER INTENT -- of the lines labelled with each, how many came back whole"
    Eval::Classifier::INTENTS.each do |intent|
      scoped = rows.select { |row| row["expected_intent"].to_s == intent.to_s }
      next if scoped.empty?

      right = scoped.count { |row| row["right"] }
      branch = scoped.count { |row| row["intent_right"] }
      say format("    %-9s %3d/%-4d whole %.3f    branch right %.3f", intent, right, scoped.size,
                 right.fdiv(scoped.size), branch.fdiv(scoped.size))
    end
  end

  def per_shape(rows)
    say "  BY SHAPE -- what the line is in the corpus for"
    rows.group_by { |row| row["shape"] }.sort.each do |shape, scoped|
      right = scoped.count { |row| row["right"] }
      say format("    %-22s %3d/%-4d %.3f", shape, right, scoped.size, right.fdiv(scoped.size))
    end
  end

  # `also_named` AS A DETECTOR. The positives are the lines the corpus says
  # named two things; see `Eval::Classifier::Bench::Reading`.
  def also_named(rows)
    tp = rows.count { |row| row["also_tp"] }
    fp = rows.count { |row| row["also_fp"] }
    fn = rows.count { |row| row["also_fn"] }
    positives = rows.count { |row| row["also_expected"] }

    say "  also_named -- the field the ruling of 2026-09-04 hangs on (PR 102 finding F4)"
    say format("    positives in the corpus  %d of %d readings", positives, rows.size)
    say format("    precision                %s   (%d right of %d answered)",
               ratio(tp, tp + fp), tp, tp + fp)
    say format("    recall                   %s   (%d found of %d there)", ratio(tp, tp + fn), tp, tp + fn)

    answered = rows.reject { |row| row["error"] }
    omitted = answered.count { |row| row["also_omitted"] }
    say format("    omission rate            %s   (%d of %d answers came back with the required field " \
               "absent or null)", ratio(omitted, answered.size), omitted, answered.size)
  end

  def refusals(rows)
    say "  REFUSAL KIND -- what the engine would say, out of Playthrough::Refusal"
    unarguable = rows.reject { |row| row["arguable"] }
    agreed = unarguable.count { |row| row["refusal_right"] }
    say format("    agreement                %s   (over the %d unarguable readings)",
               ratio(agreed, unarguable.size), unarguable.size)

    Eval::Classifier::REFUSALS.each do |kind|
      scoped = unarguable.select { |row| Array(row["expected_refusals"]).map(&:to_s).include?(kind.to_s) }
      next if scoped.empty?

      got = scoped.count { |row| row["got_refusal"].to_s == kind.to_s }
      say format("    %-24s %3d/%-4d %.3f", kind, got, scoped.size, got.fdiv(scoped.size))
    end
  end

  # THE LINES THAT WENT WRONG, WITH WHAT WAS TYPED AND WHAT CAME BACK -- the
  # whole reason a board exists. Closed-set misses first, because a right branch
  # at the wrong record is the failure the closed enum was built to prevent;
  # then wrong branches. Grouped by line, so a line that failed in every
  # repetition is one entry saying so rather than five.
  def misses(rows, sample:)
    wrong = rows.reject { |row| row["right"] }
    return say "  NOTHING MISSED. Every reading matched a labelled answer." if wrong.empty?

    grouped = wrong.group_by { |row| row["id"] }
                   .map { |id, hits| [ id, hits ] }
                   .sort_by { |id, hits| [ hits.first["closed_set_miss"] ? 0 : 1, -hits.size, id ] }

    say "  MISSED -- #{grouped.size} distinct lines, #{wrong.size} readings" \
        "#{" (first #{sample})" if grouped.size > sample}"
    grouped.first(sample).each do |id, hits|
      first = hits.first
      say format("    %-32s %s x%d", id, first["closed_set_miss"] ? "CLOSED-SET MISS" : "wrong branch  ", hits.size)
      say "      typed:    #{first["typed"].inspect}"
      say "      expected: #{Array(first["expected"]).join(" | ")}"
      say "      got:      #{hits.map { |hit| hit["got"] || hit["error"] }.uniq.join(" | ")}"
    end
  end

  def confusion
    rows = result.rows
    say
    say RULE
    say "CONFUSION -- rows are the labelled intent, columns what came back. Every arm and"
    say "repetition pooled, because this is a shape and not a rate."
    say
    header = Eval::Classifier::INTENTS.map { |intent| intent.to_s[0, 7].rjust(8) }.join
    say format("    %-9s%s", "", header)
    Eval::Classifier::INTENTS.each do |expected|
      scoped = rows.select { |row| row["expected_intent"].to_s == expected.to_s }
      next if scoped.empty?

      cells = Eval::Classifier::INTENTS.map do |got|
        count = scoped.count { |row| row["got_intent"].to_s == got.to_s }
        (count.zero? ? "." : count.to_s).rjust(8)
      end
      say format("    %-9s%s", expected, cells.join)
    end
  end

  def closing
    say
    say RULE
    say "Judge a prompt change against this with `rake eval:classifier_compare BEFORE= AFTER=`."
    say "Four repetitions a side is the arithmetic floor for a verdict -- Eval::Noise::MIN_RUNS."
    say RULE
  end

  def ratio(part, whole) = whole.zero? ? "unavailable" : format("%.3f", part.fdiv(whole))

  def say(line = "") = io&.puts(line)
end
