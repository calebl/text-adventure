# BEFORE AND AFTER, WITH A VERDICT.
#
# This is the thing the captain asked for in one sentence -- *"I just want more
# confidence that changes we are making are improving results"* -- and it is the
# only output of this module that answers a yes/no question. Score a set of runs
# on `main`, score a set on the branch, and this says, per check: REAL, NOISE,
# or INCONCLUSIVE.
#
# THE COMPARISON IS PER CHECK AND PER CORPUS, never a single number. Adding
# `still_run` (which is not a defect) to `item_not_held` (which is) would
# produce a figure that means nothing, and pooling the tuning worlds with the
# held-out one would hide the case worth seeing -- a change that improves the
# worlds it was tuned on and does nothing on the one it never saw.
#
# RICHNESS IS COMPARED THE SAME WAY AND REPORTED BESIDE, not inside. A change
# that wins REAL on contradictions and loses REAL on richness bought its number
# with blander prose, and the whole point of printing them together is that this
# case is visible at a glance rather than discoverable later.
#
# The rule and its justification are in `Eval::Noise`. `EVALUATION.md` is the
# protocol a person follows.
class Eval::Comparison
  attr_reader :before, :after, :io

  def initialize(before, after, io: $stdout)
    @before = before
    @after = after
    @io = io
  end

  # One verdict per check on one corpus.
  def verdicts(stories: nil)
    Story::Scoreboard::CHECKS.keys.map do |code|
      Eval::Noise.compare(code, before.rates(code, stories:), after.rates(code, stories:))
    end
  end

  def richness_verdict(stories: nil)
    Eval::Noise.compare(:richness, before.richness_rates(stories:), after.richness_rates(stories:))
  end

  def print
    io.puts "BEFORE #{before.name} (#{before.runs.size} runs)  ->  AFTER #{after.name} (#{after.runs.size} runs)"
    io.puts "  Verdicts: REAL means the two sets separate under an exact rank test at p<=#{Eval::Noise::ALPHA}."
    io.puts "  NOISE means they do not, and the difference is no bigger than the spread the"
    io.puts "  unchanged runs already produced. INCONCLUSIVE means neither -- usually too few runs."
    io.puts

    corpora = [ [ "tuning", Eval::TUNING ], [ "held out (#{Eval::HELD_OUT})", [ Eval::HELD_OUT ] ] ]
    corpora.each do |label, stories|
      next if before.rates(:truncated_prose, stories:).empty? && after.rates(:truncated_prose, stories:).empty?

      io.puts "  #{label}"
      io.puts format("    %-26s %14s %14s %10s  %s", "check", "before", "after", "delta", "verdict")

      verdicts(stories:).each do |verdict|
        io.puts format("    %-26s %14s %14s %10s  %s", verdict.code,
                       band(verdict.before), band(verdict.after), delta(verdict), verdict.headline)
      end

      rich = richness_verdict(stories:)
      io.puts format("    %-26s %14s %14s %10s  %s", "RICHNESS commits/turn",
                     band(rich.before, "%.2f"), band(rich.after, "%.2f"), delta(rich, "%+.2f"), rich.headline)
      io.puts "    #{richness_warning(rich, verdicts(stories:))}"
      io.puts
    end

    io.puts "Neither set is a baseline. Both are runs; re-run either and the numbers move --"
    io.puts "that is what the spreads above are for. See EVALUATION.md."
    self
  end

  private

  def band(spread, format_string = "%.3f")
    return "--" if spread.runs.zero?

    format("#{format_string} (n=%d)", spread.median, spread.runs)
  end

  def delta(verdict, format_string = "%+.3f")
    return "--" if verdict.before.runs.zero? || verdict.after.runs.zero?

    format(format_string, verdict.delta)
  end

  # THE SENTENCE THAT MAKES THE COUNTER-METRIC DO ITS JOB. A defect count that
  # fell for real while richness fell for real is not an improvement, and
  # nothing else in this report would say so.
  def richness_warning(rich, check_verdicts)
    improved = check_verdicts.select { |verdict| verdict.real? && verdict.improved? }

    if rich.real? && rich.delta.negative? && improved.any?
      "WARNING: #{improved.map(&:code).join(", ")} improved AND the prose committed to measurably less. " \
        "That trade has to be decided on purpose, not banked."
    elsif rich.real? && rich.delta.negative?
      "WARNING: the prose committed to measurably less than before."
    elsif rich.real?
      "The prose committed to measurably more."
    else
      "Richness did not move outside its own noise."
    end
  end
end
