# ONE THING A CHECKOUT HAS TO DO AFTER IT PULLS.
#
# A step is a name, a one-line reason, and a run that can be asked to write
# nothing. `Update::REGISTRY` is the list of them and its header is how to add
# one; this is the contract each one keeps.
#
# WHAT A SUBCLASS DECLARES:
#
#   .key            the step's name in the output and in `ONLY=`. A symbol, and
#                   by convention the rake task the step replaces, so the
#                   captain can still run that task by hand and recognise it.
#   .reason         one line, in the present tense, saying what it is FOR --
#                   not what it does. It is printed above every run, and it is
#                   the only place a captain reading the output learns why his
#                   database needed touching at all.
#   #call           does the work and returns a `Report`. It is handed
#                   `dry_run` and must honour it absolutely: `bin/update
#                   --dry-run` promises the captain that nothing was written,
#                   and that promise is one careless step away from being a lie.
#
# AND OPTIONALLY:
#
#   .model_calls?   THE GATE, built before anything needs it. A step that
#                   returns true is SKIPPED unless the runner was explicitly
#                   given `allow_model_calls: true` (`ALLOW_MODEL_CALLS=1`).
#                   No step returns true today and none is expected to: this
#                   runs unattended against the captain's primary database, and
#                   a step that quietly spends tokens because he pulled is the
#                   one failure mode that costs real money. `Story::Repair`'s
#                   `generate:` half is the shape of thing this is for, and it
#                   is deliberately not wired up -- `Update::Steps::SafeRepairs`
#                   passes `generate: false` and says so.
#   .reports_only?  true for a step that never writes (the doctor). The runner
#                   prints its lines every time rather than treating a run that
#                   changed nothing as silence, and it runs once instead of
#                   twice.
class Update::Step
  # WHAT A STEP DID, OR WOULD DO. Three fields and they answer three different
  # questions, which is why `changed` is not just `lines.any?`:
  #
  #   changed  did this write something (or, in a dry run, WOULD it). It is the
  #            whole of "nothing to do", and it is the thing the second run of
  #            `bin/update` against one database must report false for -- so it
  #            must count only what the step WRITES, never what it merely knows.
  #            Every backfill in this app reports outcomes it refused to act on
  #            (`ambiguous`, `unrecoverable`) on every run, for ever, because
  #            they are permanent facts about the data rather than pending work.
  #            Counting those as a change makes the tool cry wolf until nobody
  #            reads it.
  #   lines    what it wrote, one line each, already formatted.
  #   notes    permanent facts a person has to decide about -- the refusals
  #            above. Printed only when the step changed something, or under
  #            `VERBOSE=1`: `rake game:doctor` at the end of the run is where
  #            they belong when nothing else happened.
  Report = Data.define(:key, :changed, :lines, :notes) do
    def initialize(changed: false, lines: [], notes: [], **rest) = super

    def changed? = changed
    def nothing_to_do? = !changed
  end

  class << self
    def key = raise(NotImplementedError, "#{name} must declare a key")
    def reason = raise(NotImplementedError, "#{name} must declare a reason")

    # See the header. Both default to the answer every step should give.
    def model_calls? = false
    def reports_only? = false
  end

  attr_reader :dry_run

  def initialize(dry_run: false)
    @dry_run = dry_run
  end

  def dry_run? = dry_run

  def call = raise(NotImplementedError, "#{self.class.name} must implement #call")

  private

  def report(changed:, lines: [], notes: [])
    Report.new(key: self.class.key, changed: changed, lines: Array(lines), notes: Array(notes))
  end

  # Every step but the doctor walks the stories oldest first, which is the
  # order `rake game:list` and every backfill task already print in.
  def stories = Story.order(:created_at, :id)
end
