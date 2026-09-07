# EVERY REALIZATION BENCH SET ON DISK AS ONE TABLE, ACROSS MODELS AND PROMPT
# VERSIONS.
#
# The check on the whole set convention, and it is written the way
# `Eval::Prompt::Board` is written and for the same reasons: it reads
# `<set>/realization.json` and NOTHING else. No database, no key, no model, no
# corpus. If a set cannot answer for itself here, it did not record enough.
#
# TWO PLACES A SET IS READ FROM, IN ORDER -- `tmp/eval/<set>` first, then
# `db/eval/<set>`, the checked-in baseline. `Eval.set_path` is the one place
# that order lives, so a run somebody just paid for wins over one the repo ships
# under the same name.
#
# ONE COLUMN PER ARM AND NOT PER SET, because a set may hold two arms and an arm
# may have a set to itself. What is compared is measurements.
#
# IT GIVES NO VERDICTS. A band is printed and the reader can see whether two
# bands overlap, but REAL / NOISE / INCONCLUSIVE is `Eval::Noise`'s to say and
# `rake eval:realization_compare` is where it says it, two arms at a time with
# the corpus and prompt digests checked. A table of twenty verdicts read at a
# glance is exactly how a noise floor gets forgotten.
#
# MARKDOWN, DELIBERATELY: a cross-model table is read in a PR body or in
# EVALUATION.md rather than in a terminal, and a pipe table survives a column
# count nobody planned for.
class Eval::Realization::Board
  Column = Data.define(:set, :result, :arm) do
    def label = "`#{arm}`"
    def passes = result.for_arm(arm)
    def calls = passes.sum { |pass| pass.rows.size.positive? ? pass.rows.size : pass.figures["cases"].to_i }
  end

  def self.for_sets(names)
    names = Array(names)
    if names.empty?
      names = (Dir.glob(Eval.root.join("*", Eval::Realization::RESULTS)) +
               Dir.glob(Eval.kept_root.join("*", Eval::Realization::RESULTS)))
              .map { |path| File.basename(File.dirname(path)) }.uniq.sort
    end
    raise ArgumentError, "no realization bench sets to read -- run `rake eval:realization` first" if names.empty?

    new(names.map { |name| [ name, Eval::Realization::Result.load(Eval.set_path(name)) ] })
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

  # A DIGEST MISMATCH IS SAID OUT LOUD AND NOT SILENTLY TABULATED. Two sets that
  # built different rooms are not comparable at all; two on different prompt
  # versions are comparable and are the whole point, so that one is stated
  # rather than warned about.
  def warnings
    found = []
    digests = columns.map { |column| column.result.corpus_digest }.uniq

    if digests.size > 1
      found += [ "", "**READ WITH CARE: these sets did not build the same rooms** (corpus digests " \
                     "#{digests.map { |digest| "`#{digest}`" }.join(", ")}), so a difference between " \
                     "columns may be a difference in the corpus." ]
    end

    # THE QUESTIONS THIS BENCH CANNOT ANSWER ARE NOT ROWS, and a table that left
    # them out silently would read as every question asked being answered.
    # Named under it instead, with their reasons, on the same rule
    # `Story::Scoreboard` follows: unavailable, never zero.
    found << ""
    found << "Not in this table, because this bench cannot answer them, and they are **unavailable " \
             "rather than clean**:"
    Eval::Realization::UNAVAILABLE_TO_A_REALIZATION.each { |code, reason| found << "- `#{code}` — #{reason}" }

    found << ""
    found << keyword_note

    unstable = columns.reject { |column| column.result.prompt_stable }
    if unstable.any?
      found += [ "", "**#{unstable.map(&:label).uniq.join(", ")} recorded an UNSTABLE prompt**: one shape's " \
                     "designated case sent two different prompts inside one run, so the world it was " \
                     "staged in was not constant. See `Eval::Realization::Version`." ]
    end

    found
  end

  private
    # THE KEYWORD NOTE IS WRITTEN OFF THE LIST AND NOT OFF A COUNT, so this
    # sentence cannot come to disagree with the table above it: the table's rows
    # come from `Eval::Realization.checks` and `#row_label` marks them off the
    # same `KEYWORD_CHECKS` this reads, which is also what
    # `Eval::Realization::Report#checks` labels from -- so a check added to or
    # taken out of that constant moves all three at once.
    def keyword_note
      codes = Eval::Realization::Scorer::KEYWORD_CHECKS
      named = codes.map { |code| "`#{code}`" }.to_sentence
      one = codes.one?

      "#{named} #{one ? "is a **keyword check**" : "are **keyword checks**"}: " \
        "#{one ? "it reads" : "they read"} words where every other figure here compares records, so " \
        "#{one ? "its" : "their"} false-positive rate is unknown until a baseline is bought. Weigh " \
        "#{one ? "it" : "them"} accordingly — `Eval::Realization::Scorer::KEYWORD_CHECKS` says what " \
        "#{one ? "it" : "each"} can and cannot see."
    end

    # A CHECK THAT READS WORDS IS MARKED IN THE TABLE ITSELF and not only in the
    # note under it, on the same rule `Eval::Realization::Report#checks` follows:
    # the label is a fact about what the check CAN see, so it is printed wherever
    # the rate is.
    def row_label(code)
      keyword = Eval::Realization::Scorer::KEYWORD_CHECKS.include?(code) ? " **[KEYWORD]**" : ""

      "`#{code}`#{keyword}"
    end

    def body
      rows = { "set" => ->(column) { "`#{column.set}`" },
               "prompt version" => ->(column) { "`#{column.result.prompt_digest || "unrecorded"}`" },
               "corpus" => ->(column) { "`#{column.result.corpus_digest || "unrecorded"}`" },
               "reps × cases" => ->(column) { "#{column.result.reps} × #{column.result.corpus_size}" } }

      Eval::Realization.checks.each { |code| rows[row_label(code)] = ->(column) { check(column, code) } }

      Eval::Realization::Result::REPORTED_METRICS.each_key do |figure|
        rows["`#{figure}` (reported)"] = ->(column) { band(column, figure) }
      end

      rows.merge(
        "refusals" => ->(column) { band(column, :refusals) },
        "failed realizations" => ->(column) { band(column, :failures) },
        "omitted fields" => ->(column) { band(column, :omitted_fields) },
        "fields cut at the cap" => ->(column) { band(column, :cap_hits) },
        "latency median (warm)" => ->(column) { band(column, :latency_median) },
        "latency p95 (warm)" => ->(column) { band(column, :latency_p95) },
        "first realization (cold, excluded)" => ->(column) { cold(column) },
        "cost per 1,000 rooms" => ->(column) { cost(column) },
        "rotations" => ->(column) { rotations(column) }
      )
    end

    def row(label, cells) = "| #{([ label ] + cells).join(" | ")} |"

    # A RATE WITH THE COUNTS THAT MADE IT, because a check with three judgeable
    # opportunities and one flagged reads as 0.333 and is not a rate anybody
    # should act on. A check this corpus cannot judge reads `unavailable` and
    # never `0.000`.
    def check(column, code)
      judgeable = column.passes.map { |pass| pass.judgeable[code.to_s].to_i }
      return "unavailable" if judgeable.sum.zero?

      flagged = column.passes.map { |pass| pass.flagged[code.to_s].to_i }
      "#{band(column, code)} (#{flagged.min}..#{flagged.max} of #{Eval.median(judgeable).round})"
    end

    # MIN..MAX WITH THE MEDIAN, the same shape every board in this repo prints,
    # and a single number when the repetitions agreed exactly.
    def band(column, figure)
      values = column.result.values(figure, arm: column.arm).compact
      return "not recorded" if values.empty?

      spread = column.result.spread(figure, arm: column.arm)
      if Eval::Realization::Result::COUNTED.include?(figure)
        return Eval.count(spread.median) if spread.min == spread.max

        return format("%d..%d (%s)", spread.min, spread.max, Eval.count(spread.median))
      end
      return format(figure_format(figure), spread.median) if spread.min == spread.max

      format("#{figure_format(figure)}..#{figure_format(figure)} (#{figure_format(figure)})",
             spread.min, spread.max, spread.median)
    end

    def figure_format(figure)
      return "%.2fs" if Eval::Realization::Result::SECONDS.include?(figure)
      return "%.2f" if Eval::Realization::Result::MEANS.include?(figure)

      "%.3f"
    end

    # WHAT A THOUSAND ROOMS COST ON THIS ARM -- the figure that decides whether a
    # model is worth building worlds on, priced on
    # `Eval::Realization::PER_CALL`, measured over the real realization calls in
    # the captain's own database rather than modelled. Both calls, because a
    # room costs both.
    def cost(column)
      arm = Eval::Classifier::Arm.parse(column.arm)
      return "free (the captain's own hardware)" if arm.local?
      return "unpriced -- the registry has no row" if arm.price == Eval::Cost::UNKNOWN

      input = Eval::Realization::CALLS.sum { |call| Eval::Realization::PER_CALL.fetch(call)[:input] }
      output = Eval::Realization::CALLS.sum { |call| Eval::Realization::PER_CALL.fetch(call)[:output] }
      format("$%.2f", arm.price.of(input * 1_000, output * 1_000))
    end

    def cold(column)
      warmup = column.result.warmup(column.arm)
      return "not recorded" if warmup.nil? || warmup["seconds"].nil?

      format("%.1fs", warmup["seconds"])
    end

    def rotations(column)
      count = column.passes.sum(&:rotations)
      return "0 of #{column.calls}" if count.zero?

      "**#{count} of #{column.calls} -- another model answered**"
    end
end
