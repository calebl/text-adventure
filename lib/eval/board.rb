# THE BOARD: what the sweep found, what it cost, and how far its own numbers
# wander when nothing changed.
#
# READ IT IN THIS ORDER, which is the order it prints:
#
#   1. WHAT IT COST and what ran. A board whose spend is not on it invites the
#      next sweep to be run without thinking about the last one.
#   2. THE NOISE FLOOR, first and not last, because every number under it has
#      to be read against it. Per check, per world: the min, the median and the
#      max over runs that differed in nothing but what the models sampled.
#   3. THE RATES, tuning worlds and the held-out world reported apart and never
#      pooled. A check the runs could not answer says UNAVAILABLE; it is never
#      printed as a zero.
#   4. RICHNESS, beside the rates and never folded into them. The counter-metric
#      -- see `Eval::Richness` for the hazard it exists to catch.
#   5. THE FLAGGED TURNS, each with what was typed, the passage and the record
#      it contradicts. This is the captain's accuracy pass and the reason the
#      whole thing prints at all: his attention goes only to what a check
#      caught.
class Eval::Board
  attr_reader :set, :io

  def initialize(set, io: $stdout)
    @set = set
    @io = io
  end

  # How many flagged turns to print in full. A bounded sample, because the
  # accuracy pass is a person reading passages and an unbounded list is a list
  # nobody finishes. `SAMPLE=n` on the rake task moves it.
  DEFAULT_SAMPLE = 24

  def print(sample: DEFAULT_SAMPLE)
    header
    noise_floor
    rates
    richness
    findings(sample)
    footer
    self
  end

  private

  def header
    cost = set.cost
    io.puts "EVALUATION BOARD -- #{set.name}"
    io.puts "  #{set.runs.size} runs over #{set.stories.size} worlds, #{set.turns} scored turns"
    io.puts "  pinned on: #{set.models.join(", ").presence || "unrecorded"}"
    io.puts "  tuning: #{Eval::TUNING.join(", ")}"
    io.puts "  held out: #{Eval::HELD_OUT} (no check was measured against it -- see Eval::HELD_OUT)"
    io.puts format("  spend: $%.4f over %d model calls (%s in / %s out)",
                   cost.dollars, cost.calls, cost.input_tokens.to_fs(:delimited), cost.output_tokens.to_fs(:delimited))
    io.puts "  UNPRICED, so the figure above is low: #{cost.unpriced.join(", ")}" if cost.unpriced.any?
    failures = set.runs.sum { |run| run.failures.size }
    io.puts "  #{failures} turn(s) failed outright and produced no passage" if failures.positive?
    io.puts
  end

  # ------------------------------------------------------------------ 2
  def noise_floor
    io.puts "THE NOISE FLOOR -- what these numbers do when NOTHING changed."
    io.puts "  Runs of one world differ only in what the models sampled. Anything inside this"
    io.puts "  spread is not evidence. #{Eval::Noise::MIN_RUNS} runs a side are needed before a difference gets a verdict;"
    io.puts "  see EVALUATION.md for the rule and `rake eval:compare` for the verdict itself."
    io.puts

    set.stories.each do |story|
      reps = set.reps_of(story)
      io.puts "  #{story}#{" [HELD OUT]" if Eval.held_out?(story)} -- #{reps} run#{"s" unless reps == 1}"
      if reps < 2
        io.puts "    one run: a spread needs at least two, and a verdict needs #{Eval::Noise::MIN_RUNS}. REPS=#{Eval::Noise::MIN_RUNS} or more."
        io.puts
        next
      end

      io.puts format("    %-26s %-22s %s", "check", "flags per run", "rate min..max (median)")
      Story::Scoreboard::CHECKS.each_key do |code|
        runs = set.for_story(story)
        next io.puts(format("    %-26s %s", code, "UNAVAILABLE on this world")) unless runs.any? { |run| run.available?(code) }

        counts = runs.map { |run| run.flagged(code) }
        band = set.spread(code, story)
        io.puts format("    %-26s %-22s %s", code, counts.join(", "),
                       format("%.3f..%.3f (%.3f)", band.min, band.max, band.median))
      end

      band = set.richness_spread(story)
      io.puts format("    %-26s %-22s %s", "RICHNESS commitments/turn",
                     set.for_story(story).map { |run| format("%.2f", run.richness.commitments) }.join(", "),
                     format("%.2f..%.2f (%.2f)", band.min, band.max, band.median))
      io.puts
    end
  end

  # ------------------------------------------------------------------ 3
  def rates
    io.puts "THE RATES, by corpus. Tuning and held out are never pooled."
    io.puts
    group("tuning (#{Eval::TUNING.join(" + ")})", set.tuning)
    group("held out (#{Eval::HELD_OUT})", set.held_out)
  end

  def group(label, runs)
    return if runs.empty?

    io.puts "  #{label} -- #{runs.size} run#{"s" unless runs.one?}, #{runs.sum(&:scenes)} turns"
    io.puts format("    %-26s %8s %10s %7s  %s", "check", "flagged", "rate", "turns", "what it counts")

    Story::Scoreboard::CHECKS.each do |code, description|
      answering = runs.select { |run| run.available?(code) }
      if answering.empty?
        io.puts format("    %-26s %8s %10s %7s  %s", code, "--", "UNAVAIL", "--", description)
        next
      end

      flagged = answering.sum { |run| run.flagged(code) }
      judgeable = answering.sum { |run| run.reading(code).judgeable }
      unjudged = answering.sum { |run| run.reading(code).unjudged }
      rate = judgeable.positive? ? flagged.fdiv(judgeable) : 0.0
      note = unjudged.positive? ? "#{description} (#{unjudged} unjudged)" : description
      # DISTINCT TURNS AS WELL AS FLAGS, because they are different questions
      # and the rate answers only the first. One passage earns two
      # `third_person_protagonist` flags when it writes both "Isbet Marrow" and
      # "Marrow", so a rate above the share of turns affected is normal and is
      # not a bug -- but "how often does this happen to a player" is the turn
      # column, not the rate.
      turns = answering.sum { |run| run.findings.select { |finding| finding.code == code }.map(&:turn).uniq.size }
      io.puts format("    %-26s %8s %9.1f%% %7s  %s", code, "#{flagged}/#{judgeable}", rate * 100,
                     "#{turns}/#{judgeable}", note)
    end
    io.puts
  end

  # ------------------------------------------------------------------ 4
  def richness
    io.puts "RICHNESS -- what the prose committed to. NOT a quality score, and never added to"
    io.puts "  the rates above. It is here so a fall in contradictions can be checked against"
    io.puts "  what it cost: prose that names nothing cannot contradict anything. See Eval::Richness."
    io.puts
    io.puts format("    %-34s %7s %7s %8s %9s %7s %7s %7s %7s",
                   "corpus", "chars", "words", "commit", "coverage", "room", "exits", "items", "people")

    [ [ "tuning", set.tuning ], [ "held out (#{Eval::HELD_OUT})", set.held_out ] ].each do |label, runs|
      next if runs.empty?

      row = combined_richness(runs)
      io.puts format("    %-34s %7d %7d %8.2f %8.0f%% %7.2f %7.2f %7.2f %7.2f",
                     label, row.chars, row.words, row.commitments, row.coverage * 100,
                     row.room, row.exits, row.items, row.characters)
    end
    io.puts
  end

  # The median of each run's median. Two levels, because a run is the unit that
  # varies and a turn is the unit that is measured -- averaging every turn
  # together would let one long run outvote three short ones.
  def combined_richness(runs)
    rows = runs.map(&:richness)
    Eval::Richness::Summary.new(
      turns: rows.sum(&:turns),
      chars: Eval.median(rows.map(&:chars)).round,
      words: Eval.median(rows.map(&:words)).round,
      commitments: Eval.median(rows.map(&:commitments)).round(2),
      coverage: Eval.median(rows.map(&:coverage)).round(4),
      room: Eval.median(rows.map(&:room)).round(2),
      exits: Eval.median(rows.map(&:exits)).round(2),
      items: Eval.median(rows.map(&:items)).round(2),
      characters: Eval.median(rows.map(&:characters)).round(2)
    )
  end

  # ------------------------------------------------------------------ 5
  # ONE ROW PER PASSAGE FOR THE ACCURACY PASS, not one per flag. A narration
  # that names the protagonist in full earns a flag for "Isbet Marrow" and
  # another for "Marrow", and printing the same sentence twice wastes the
  # attention this section exists to spend carefully. The counts above are
  # untouched.
  def findings(sample)
    all = set.runs.flat_map { |run| run.findings.map { |finding| [ run, finding ] } }
                  .uniq { |run, finding| [ run.label, finding.code, finding.turn, finding.claim ] }
    if all.empty?
      io.puts "NOTHING FLAGGED. On a game with two open narration bugs that is a claim about the"
      io.puts "  checks, not about the game -- read `Eval::Noise` and go looking for what they missed."
      io.puts
      return
    end

    order = Story::Scoreboard::CHECKS.keys
    all.sort_by! { |run, finding| [ order.index(finding.code) || 99, run.story, run.rep, finding.turn.to_s ] }

    io.puts "FLAGGED TURNS -- #{all.size} in all, showing #{[ sample, all.size ].min}."
    io.puts "  Each one: the run, the turn, what was typed, and the passage against the record."
    io.puts "  THE HONEST QUESTION FOR EACH IS: is this really wrong?"
    io.puts

    all.first(sample).each_with_index do |(run, finding), index|
      io.puts format("  %2d. [%s] %s r%d %s%s", index + 1, finding.code, WorldSeed.slug(run.story), run.rep,
                     finding.turn || "?", run.held_out? ? "  [HELD OUT]" : "")
      io.puts "      typed:   #{finding.typed.to_s.strip.truncate(120)}" if finding.typed.present?
      io.puts "      says:    #{finding.headline}"
      io.puts "      passage: #{finding.claim.to_s.strip.truncate(260)}" if finding.claim.present?
      io.puts "      record:  #{finding.evidence["records say"] || finding.evidence["was offered"] || finding.where}"
      io.puts
    end

    remaining = all.size - sample
    io.puts "  ...and #{remaining} more. SAMPLE=#{all.size} to print them all." if remaining.positive?
    io.puts
  end

  def footer
    io.puts "Scoring is offline, deterministic and free -- no model call, no API key, no network."
    io.puts "Re-score any set with `rake eval:score SET=#{set.path&.basename || set.name}`."
  end
end
