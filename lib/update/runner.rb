# RUNS THE REGISTRY, IN ORDER, AND SAYS WHAT HAPPENED.
#
# DRY FIRST AND THEN REAL, per step, and that is the shape of the whole thing:
# every step is asked what it WOULD do, and only a step that answers "something"
# is then asked to do it. Two consequences worth having --
#
#   * a step with nothing to do costs one line of output and no write at all,
#     which is what makes `bin/update` runnable after every pull rather than
#     only after the pulls a captain suspects;
#   * the captain reads the plan and the result side by side for the run that
#     actually happened, rather than being told to run it twice himself.
#
# It is not one transaction, on `Story::Repair#apply!`'s own reasoning: the
# steps are independent and the work a step completed before a later one failed
# is still work the database wanted.
#
# A FAILURE STOPS THE RUN AND NAMES THE STEP. The steps are in dependency order
# (`Update::REGISTRY`), so carrying on past a failure means running a step
# against exactly the half-updated database its predecessor was supposed to
# prevent.
class Update::Runner
  # ONE STEP'S RESULT. `dry` is what it said it would do and `real` what it
  # then did -- nil when the step was not asked, which is a dry run, a step
  # with nothing to do, or a report-only step.
  Outcome = Data.define(:step, :dry, :real, :error, :skipped) do
    def initialize(dry: nil, real: nil, error: nil, skipped: false, **rest) = super

    def failed? = !error.nil?
    def changed? = !skipped && !failed? && (dry&.changed? || false)
    def report = real || dry
  end

  attr_reader :steps, :dry_run, :allow_model_calls, :verbose, :out, :outcomes

  def initialize(steps: Update::REGISTRY, dry_run: false, allow_model_calls: false, verbose: false, out: $stdout)
    @steps = steps
    @dry_run = dry_run
    @allow_model_calls = allow_model_calls
    @verbose = verbose
    @out = out
    @outcomes = []
  end

  def dry_run? = dry_run

  # Runs every step until one fails. Returns the outcomes; `#failed` is the
  # one that stopped it, if any.
  def run
    steps.each do |step|
      outcome = run_step(step)
      outcomes << outcome
      break if outcome.failed?
    end

    outcomes
  end

  def failed = outcomes.find(&:failed?)
  def failed? = !failed.nil?
  def changed = outcomes.select(&:changed?)

  private

  def run_step(step)
    heading(step)

    return skip_for_a_model_call(step) if step.model_calls? && !allow_model_calls

    # A report-only step writes nothing whatever it is asked, so asking it
    # twice would print the same paragraph twice.
    return report_only(step) if step.reports_only?

    dry = step.new(dry_run: true).call
    if dry.nothing_to_do?
      say "     nothing to do"
      print_notes(dry) if verbose
      return Outcome.new(step: step, dry: dry)
    end

    print_lines("would", dry)
    return Outcome.new(step: step, dry: dry) if dry_run?

    real = step.new(dry_run: false).call
    print_lines("did", real)
    print_notes(real)

    Outcome.new(step: step, dry: dry, real: real)
  rescue StandardError => e
    say "     FAILED -- #{e.class}: #{e.message}"
    Outcome.new(step: step, error: e)
  end

  def report_only(step)
    report = step.new(dry_run: dry_run).call
    report.lines.each { |line| say "     #{line}" }
    print_notes(report)

    Outcome.new(step: step, dry: report)
  end

  # NOT A FAILURE. Nothing in the registry needs a model call, so this branch
  # exists to be correct rather than to be reached; if something ever does, a
  # captain who did not ask for it gets a run that finished and a sentence
  # saying what it left alone.
  def skip_for_a_model_call(step)
    say "     skipped -- it needs a model call, and this never spends tokens because you pulled."
    say "     Opt in with: ALLOW_MODEL_CALLS=1 bin/rails game:update"

    Outcome.new(step: step, skipped: true)
  end

  def heading(step)
    say "  -> #{step.key} -- #{step.reason}"
  end

  def print_lines(label, report)
    report.lines.each_with_index do |line, index|
      say format("     %-6s %s", index.zero? ? "#{label}:" : "", line)
    end
  end

  def print_notes(report)
    return if report.notes.empty?

    report.notes.each { |note| say "     note: #{note}" }
  end

  def say(line) = out.puts(line)
end
