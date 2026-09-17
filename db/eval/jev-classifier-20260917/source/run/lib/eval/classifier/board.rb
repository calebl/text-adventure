# EVERY BENCH SET ON DISK AS ONE TABLE, ACROSS MODELS.
#
# THE CAPTAIN'S INSTRUCTION OF 2026-09-04: *"produce one cross-model table
# covering mistral, minimax and the three local models on accuracy, also_named
# precision/recall, closed-set misses, latency, failures."* This is the thing
# that prints it, so the table in a PR body is reproducible rather than
# hand-assembled -- and it is a check on the set convention besides: it reads
# `tmp/eval/<set>/classifier.json` and NOTHING else. No database, no key, no
# model, no corpus. If a set cannot answer for itself here, it did not record
# enough.
#
# ONE COLUMN PER ARM AND NOT PER SET, because a set may hold two arms (the
# hosted pair is measured in one run) and an arm may have a set to itself (a
# local model runs contiguously, so it must). What is compared is models.
#
# ONE EXCEPTION TO "the stored file and nothing else": THE COST ROW reads the
# `models` registry, because a set does not record what its calls were priced
# at. A model the registry has never heard of reads `unpriced` rather than as
# free -- the same rule `Eval::Cost#price` follows -- and the rest of the table
# is unaffected either way.
#
# MARKDOWN, DELIBERATELY. `Eval::Classifier::Report` prints for a terminal; this
# prints for the place a cross-model comparison is actually read, which is a PR
# body or EVALUATION.md. A pipe table also survives a column count nobody
# planned for, which a fixed-width board does not.
#
# IT GIVES NO VERDICTS. A band is printed and the reader can see whether two
# bands overlap, but REAL / NOISE / INCONCLUSIVE is `Eval::Noise`'s to say and
# `rake eval:classifier_compare` is where it says it, two arms at a time with
# the corpus digests checked. A table of twenty verdicts read at a glance is
# exactly how a noise floor gets forgotten.
class Eval::Classifier::Board
  # The figures, in the order a reader wants them: what it got right, then what
  # it got wrong in the way that matters, then the detector, then speed, then
  # whether the calls even landed.
  FIGURES = %i[strict_accuracy accuracy intent_accuracy refusal_agreement closed_set_misses].freeze

  Column = Data.define(:set, :result, :arm) do
    def parsed_arm = Eval::Classifier::Arm.parse(arm)
    def local? = parsed_arm.local?
    def jev? = parsed_arm.jev?
    def label = "`#{arm}`#{" *(local)*" if local?}"
    # READ AS COUNTS AND NEVER AS ROWS, so a checked-in SUMMARY set -- which has
    # no rows on purpose -- prints the same table as the whole run it came from.
    # `Stored#also_counts` answers from the field when the field is there and by
    # counting when it is not.
    def counts
      result.for_arm(arm).map(&:also_counts)
            .each_with_object(Hash.new(0)) { |row, all| row.each { |key, value| all[key] += value } }
    end

    def calls = counts[:readings_count]
    def rotations = result.for_arm(arm).sum(&:rotations)
  end

  def self.for_sets(names)
    names = Array(names)
    if names.empty?
      names = Dir.glob(Eval.root.join("*", Eval::Classifier::RESULTS))
                 .map { |path| File.basename(File.dirname(path)) }.sort
    end
    raise ArgumentError, "no bench sets to read -- run `rake eval:classifier` first" if names.empty?

    new(names.map { |name| [ name, Eval::Classifier::Result.load(Eval.set_path(name)) ] })
  end

  def initialize(pairs)
    @columns = pairs.flat_map do |name, result|
      result.arms.map { |arm| Column.new(set: name, result: result, arm: arm) }
    end
  end

  attr_reader :columns

  def print(io = $stdout)
    lines.each { |line| io.puts(line) }
    warnings.each { |line| io.puts(line) }
  end

  def lines
    [ row("figure", columns.map(&:label)), row("---", columns.map { "---" }) ] +
      body.map { |label, cell| row(label, columns.map { |column| cell.call(column) }) }
  end

  # A DIGEST MISMATCH IS SAID OUT LOUD AND NOT SILENTLY TABULATED. Two sets
  # scored on different labels are not comparable, and a table is the easiest
  # place in the world to forget that.
  def warnings
    digests = columns.map { |column| column.result.corpus_digest }.uniq
    identities = columns.filter_map { |column| column.result.request_identity }.uniq
    schema_warning = identities.size > 1 ? [ "WARNING: these sets recorded different schema request identities." ] : []
    return schema_warning if digests.size <= 1

    schema_warning + [ "", "**READ WITH CARE: these sets were not scored on the same corpus** (digests " \
          "#{digests.map { |digest| "`#{digest}`" }.join(", ")}), so a difference between " \
          "columns may be a difference in the labels." ]
  end

  private
    def body
      rows = { "schema request" => ->(column) { Eval::RequestIdentity.label(column.result.request_identity) },
               "set" => ->(column) { "`#{column.set}`" },
               "reps × lines" => ->(column) { "#{column.result.reps} × #{column.result.corpus_size}" },
               # PRINTED BESIDE THE LATENCY COLUMNS BECAUSE IT IS THE ONLY THING
               # ON THE BOARD THAT MOVES THEM. A serial set reads 1; two columns
               # with different numbers here have latencies that are not
               # comparable and accuracies that are.
               "concurrency" => ->(column) { column.result.concurrency.to_s } }

      FIGURES.each { |figure| rows["`#{figure}`"] = ->(column) { band(column, figure) } }

      rows.merge(
        "`also_named` precision" => ->(column) { precision(column) },
        "`also_named` recall" => ->(column) { recall(column) },
        "omission rate" => ->(column) { omission(column) },
        "Jev confidence distribution" => ->(column) { confidence_distribution(column) },
        "Jev coverage by floor" => ->(column) { confidence_coverage(column) },
        "Jev wrong at confidence ≥0.6" => ->(column) { wrong_high_confidence(column) },
        "Jev low-confidence fallback @0.6" => ->(column) { low_confidence_fallback(column) },
        "Jev actual billed cost" => ->(column) { actual_billed_cost(column) },
        "latency median (warm)" => ->(column) { band(column, :latency_median) },
        "latency p95 (warm)" => ->(column) { band(column, :latency_p95) },
        "first call (cold, excluded)" => ->(column) { cold(column) },
        "cost per 1,000 calls" => ->(column) { cost(column) },
        "failed calls" => ->(column) { band(column, :failures) },
        "rotations" => ->(column) { rotations(column) }
      )
    end

    def row(label, cells) = "| #{([ label ] + cells).join(" | ")} |"

    # MIN..MAX WITH THE MEDIAN, the same shape every board in this repo prints,
    # and a single number when the repetitions agreed exactly -- a range of
    # `0.980..0.980` reads as noise nobody measured.
    def band(column, figure)
      values = column.result.values(figure, arm: column.arm).compact
      return "not recorded" if values.empty?

      spread = column.result.spread(figure, arm: column.arm)
      # A COUNT KEEPS ITS HALF. See `Eval.count`: the median of four counts is
      # fractional half the time, and printing 9.5 as 9 understates the figure
      # `closed_set_misses` exists to state.
      if Eval::Classifier::Result::COUNTED.include?(figure)
        return Eval.count(spread.median) if spread.min == spread.max

        return format("%d..%d (%s)", spread.min, spread.max, Eval.count(spread.median))
      end
      return format(figure_format(figure), spread.median) if spread.min == spread.max

      format("#{figure_format(figure)}..#{figure_format(figure)} (#{figure_format(figure)})",
             spread.min, spread.max, spread.median)
    end

    def figure_format(figure)
      return "%.2fs" if Eval::Classifier::Result::SECONDS.include?(figure)

      "%.3f"
    end

    def precision(column)
      counts = column.counts
      answered = counts[:also_tp] + counts[:also_fp]
      return "no second name answered" if answered.zero?

      format("%.3f (%d of %d)", counts[:also_tp].fdiv(answered), counts[:also_tp], answered)
    end

    def recall(column)
      counts = column.counts
      there = counts[:also_tp] + counts[:also_fn]
      return "--" if there.zero?

      format("%.3f (%d of %d)", counts[:also_tp].fdiv(there), counts[:also_tp], there)
    end

    # THE FIGURE PR 102's FINDING F4 ASKED FOR, over the calls that ANSWERED:
    # a failed call has no provider JSON to read a missing field out of.
    def omission(column)
      counts = column.counts
      return "no answers" if counts[:answered].zero?

      format("%.3f (%d of %d)", counts[:also_omitted].fdiv(counts[:answered]),
             counts[:also_omitted], counts[:answered])
    end

    # WHAT A THOUSAND CLASSIFIER CALLS COST ON THIS ARM, which is the figure that
    # makes a cheaper model worth asking about at all: priced on
    # `Eval::Classifier::PER_CALL`, measured over the 61 real classifier calls in
    # the captain's own database rather than modelled.
    def cost(column)
      price = column.parsed_arm.price
      return "free (the captain's own hardware)" if column.local?
      return "unpriced -- the registry has no row" if price == Eval::Cost::UNKNOWN
      if column.jev? && column.result.jev_evidence(column.arm).any?
        calls = [ column.calls, 1 ].max
        return format("$%.2f (from actual receipts)", column.result.actual_billed_cost(column.arm) * 1_000 / calls)
      end

      per_call = Eval::Classifier::PER_CALL
      format("$%.2f", price.of(per_call[:input] * 1_000, per_call[:output] * 1_000))
    end

    def confidence_distribution(column)
      evidence = column.result.jev_evidence(column.arm)
      return "--" if evidence.empty?

      %w[min p25 median p75 p95 max].map do |key|
        values = evidence.map { |row| indifferent(indifferent(row, "confidence"), key).to_f }
        "#{key}=#{format('%.3f', Eval.median(values))}"
      end.join(" / ")
    end

    def confidence_coverage(column)
      evidence = column.result.jev_evidence(column.arm)
      return "--" if evidence.empty?

      Eval::Classifier::JevAgent::CONFIDENCE_FLOORS.map do |floor|
        key = format("%.1f", floor)
        rates = evidence.map { |row| indifferent(indifferent(indifferent(row, "floors"), key), "coverage").to_f }
        "#{key}:#{format('%.3f', Eval.median(rates))}"
      end.join(" / ")
    end

    def wrong_high_confidence(column)
      evidence = column.result.jev_evidence(column.arm)
      return "--" if evidence.empty?

      values = evidence.map do |row|
        indifferent(indifferent(indifferent(row, "floors"), "0.6"), "wrong").to_i
      end
      spread_count(values)
    end

    def low_confidence_fallback(column)
      evidence = column.result.jev_evidence(column.arm)
      return "--" if evidence.empty?

      rates = evidence.map { |row| indifferent(row, "low_confidence_fallback_rate").to_f }
      format_rate_band(rates)
    end

    def actual_billed_cost(column)
      return "--" unless column.jev?

      usage = column.result.actual_usage(column.arm)
      format("$%.6f (%d input / %d output tokens, warm-up included)",
             column.result.actual_billed_cost(column.arm), usage[:input_tokens], usage[:output_tokens])
    end

    def spread_count(values)
      spread = Eval::Noise.spread(:count, values)
      return Eval.count(spread.median) if spread.min == spread.max

      format("%d..%d (%s)", spread.min, spread.max, Eval.count(spread.median))
    end

    def format_rate_band(values)
      spread = Eval::Noise.spread(:rate, values)
      return format("%.3f", spread.median) if spread.min == spread.max

      format("%.3f..%.3f (%.3f)", spread.min, spread.max, spread.median)
    end

    def indifferent(hash, key)
      hash[key] || hash[key.to_sym]
    end

    def cold(column)
      warmup = column.result.warmup(column.arm)
      return "not recorded" if warmup.nil? || warmup["seconds"].nil?

      # The residency answer is only meaningful for a local arm -- a hosted
      # provider has no model to keep in memory, and printing `not_local` in a
      # cross-model table is noise in the column that matters least.
      residency = column.local? ? warmup["residency"].presence : nil
      format("%.1fs%s", warmup["seconds"], residency ? " (#{residency})" : "")
    end

    def rotations(column)
      count = column.rotations
      return "0 of #{column.calls}" if count.zero?

      "**#{count} of #{column.calls} -- another model answered**"
    end
end
