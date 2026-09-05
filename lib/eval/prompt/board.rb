# EVERY PROMPT BENCH SET ON DISK AS ONE TABLE, ACROSS MODELS AND PROMPT
# VERSIONS.
#
# The check on the whole set convention, and it is written the way
# `Eval::Classifier::Board` is written and for the same reasons: it reads
# `<set>/prompt.json` and NOTHING else. No database, no key, no model, no
# corpus. If a set cannot answer for itself here, it did not record enough.
#
# TWO PLACES A SET IS READ FROM, IN ORDER -- `tmp/eval/<set>` first, then
# `db/eval/<set>`, the checked-in baseline. `Eval.set_path` is the one place
# that order lives, so a run somebody just paid for wins over one the repo ships
# under the same name. Nothing writes to `db/eval` except a person deciding to
# keep a set.
#
# ONE COLUMN PER ARM AND NOT PER SET, because a set may hold two arms and an arm
# may have a set to itself. What is compared is measurements.
#
# IT GIVES NO VERDICTS. A band is printed and the reader can see whether two
# bands overlap, but REAL / NOISE / INCONCLUSIVE is `Eval::Noise`'s to say and
# `rake eval:prompt_compare` is where it says it, two arms at a time with the
# corpus and prompt digests checked. A table of twenty verdicts read at a glance
# is exactly how a noise floor gets forgotten.
#
# MARKDOWN, DELIBERATELY: a cross-model table is read in a PR body or in
# EVALUATION.md rather than in a terminal, and a pipe table survives a column
# count nobody planned for.
class Eval::Prompt::Board
  Column = Data.define(:set, :result, :arm) do
    def label = "`#{arm}`"
    def passes = result.for_arm(arm)
    def calls = passes.sum { |pass| pass.rows.size.positive? ? pass.rows.size : pass.figures["cases"].to_i }
  end

  def self.for_sets(names)
    names = Array(names)
    if names.empty?
      names = (Dir.glob(Eval.root.join("*", Eval::Prompt::RESULTS)) +
               Dir.glob(Eval.kept_root.join("*", Eval::Prompt::RESULTS)))
              .map { |path| File.basename(File.dirname(path)) }.uniq.sort
    end
    raise ArgumentError, "no prompt bench sets to read -- run `rake eval:prompt` first" if names.empty?

    new(names.map { |name| [ name, Eval::Prompt::Result.load(Eval.set_path(name)) ] })
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
  # scored on different cases are not comparable at all; two on different prompt
  # versions are comparable and are the whole point, so that one is stated
  # rather than warned about.
  def warnings
    found = []
    digests = columns.map { |column| column.result.corpus_digest }.uniq

    if digests.size > 1
      found += [ "", "**READ WITH CARE: these sets did not score the same cases** (corpus digests " \
                     "#{digests.map { |digest| "`#{digest}`" }.join(", ")}), so a difference between " \
                     "columns may be a difference in the corpus." ]
    end

    # THE FOUR CHECKS A SINGLE TURN CANNOT ANSWER ARE NOT ROWS, and a table that
    # left them out silently would read as eight checks passing where twelve
    # were asked. Named under it instead, with their reasons, on the same rule
    # `Story::Scoreboard` follows: unavailable, never zero.
    found << ""
    found << "Not in this table, because one turn cannot answer them, and they are **unavailable rather " \
             "than clean**:"
    Eval::Prompt::UNAVAILABLE_TO_A_CASE.each { |code, reason| found << "- `#{code}` — #{reason}" }

    unstable = columns.reject { |column| column.result.prompt_stable }
    if unstable.any?
      found += [ "", "**#{unstable.map(&:label).uniq.join(", ")} recorded an UNSTABLE prompt**: one shape's " \
                     "designated case sent two different prompts inside one run, so its facts were not " \
                     "constant. See `Eval::Prompt::Version`." ]
    end

    found
  end

  private
    def body
      rows = { "set" => ->(column) { "`#{column.set}`" },
               "prompt version" => ->(column) { "`#{column.result.prompt_digest || "unrecorded"}`" },
               "corpus" => ->(column) { "`#{column.result.corpus_digest || "unrecorded"}`" },
               "reps × cases" => ->(column) { "#{column.result.reps} × #{column.result.corpus_size}" } }

      Eval::Prompt.checks.each { |code| rows["`#{code}`"] = ->(column) { check(column, code) } }

      rows.merge(
        "`words` (richness)" => ->(column) { band(column, :words) },
        "`commitments` (richness)" => ->(column) { band(column, :commitments) },
        "refusals" => ->(column) { band(column, :refusals) },
        "failed calls" => ->(column) { band(column, :failures) },
        "omitted fields" => ->(column) { band(column, :omitted_fields) },
        "fields cut at the cap" => ->(column) { band(column, :cap_hits) },
        "latency median (warm)" => ->(column) { band(column, :latency_median) },
        "latency p95 (warm)" => ->(column) { band(column, :latency_p95) },
        "first call (cold, excluded)" => ->(column) { cold(column) },
        "cost per 1,000 narrations" => ->(column) { cost(column) },
        "rotations" => ->(column) { rotations(column) }
      )
    end

    def row(label, cells) = "| #{([ label ] + cells).join(" | ")} |"

    # A RATE WITH THE COUNTS THAT MADE IT, because a check with three judgeable
    # cases and one flagged reads as 0.333 and is not a rate anybody should act
    # on. A check the corpus cannot judge reads `unavailable` and never `0.000`.
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
      if Eval::Prompt::Result::COUNTED.include?(figure)
        return Eval.count(spread.median) if spread.min == spread.max

        return format("%d..%d (%s)", spread.min, spread.max, Eval.count(spread.median))
      end
      return format(figure_format(figure), spread.median) if spread.min == spread.max

      format("#{figure_format(figure)}..#{figure_format(figure)} (#{figure_format(figure)})",
             spread.min, spread.max, spread.median)
    end

    def figure_format(figure)
      return "%.2fs" if Eval::Prompt::Result::SECONDS.include?(figure)

      "%.3f"
    end

    # WHAT A THOUSAND NARRATED TURNS COST ON THIS ARM -- the figure that decides
    # whether a model is worth playing on, priced on `Eval::Prompt::PER_CALL`,
    # measured over the real prose calls in the captain's own database rather
    # than modelled. The narration pass, because it is the one a player waits
    # for on nearly every turn.
    def cost(column)
      price = Eval::Classifier::Arm.parse(column.arm).price
      return "free (the captain's own hardware)" if Eval::Classifier::Arm.parse(column.arm).local?
      return "unpriced -- the registry has no row" if price == Eval::Cost::UNKNOWN

      per = Eval::Prompt::PER_CALL.fetch("narration")
      format("$%.2f", price.of(per[:input] * 1_000, per[:output] * 1_000))
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
