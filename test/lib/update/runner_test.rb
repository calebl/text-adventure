require "test_helper"

# THE MACHINERY, WITH FAKE STEPS. What a step does is its own test
# (`Update::StepsTest`); this is about the four promises the runner makes to
# every step in the registry, present and future:
#
#   order          the registry's order is the run's order, because it is
#                  dependency order and nothing else infers it.
#   quiet          a step with nothing to do costs one line and no write.
#   stop and name  a failure stops the run and says which step it was.
#   dry means dry  in a dry run the real pass is never asked for at all.
#
# The fake steps record what they were asked, which is the only way to assert
# the fourth: "wrote nothing" is not observable from outside, but "was never
# asked to write" is.
class Update::RunnerTest < ActiveSupport::TestCase
  # A step that answers however the test needs and remembers being called.
  class Recorder < Update::Step
    class << self
      attr_accessor :calls, :answer, :raises

      def key = :recorder
      def reason = "a fake step"

      def reset!(answer: { changed: false }, raises: nil)
        self.calls = []
        self.answer = answer
        self.raises = raises
      end
    end

    def call
      self.class.calls << dry_run
      raise self.class.raises if self.class.raises

      Update::Step::Report.new(key: self.class.key, **self.class.answer)
    end
  end

  class First < Recorder
    def self.key = :first
  end

  class Second < Recorder
    def self.key = :second
  end

  class Reporter < Recorder
    def self.key = :reporter
    def self.reports_only? = true
  end

  class NeedsAModel < Recorder
    def self.key = :needs_a_model
    def self.model_calls? = true
  end

  def setup
    [ First, Second, Reporter, NeedsAModel ].each(&:reset!)
    @out = StringIO.new
  end

  def run_with(steps, **options)
    Update::Runner.new(steps: steps, out: @out, **options).tap(&:run)
  end

  def output = @out.string

  test "the steps run in the order the registry lists them" do
    order = []
    First.reset!(answer: { changed: true, lines: [ "first did it" ] })
    Second.reset!(answer: { changed: true, lines: [ "second did it" ] })

    run_with([ First, Second ])

    order = output.lines.grep(/->/).map(&:strip)
    assert_equal [ "-> first -- a fake step", "-> second -- a fake step" ], order
    assert_operator output.index("first did it"), :<, output.index("second did it")
  end

  test "a step with nothing to do says so once and is never asked to write" do
    run_with([ First ])

    assert_match(/nothing to do/, output)
    assert_equal [ true ], First.calls, "the real pass was asked for after a dry pass that found nothing"
  end

  test "a step with something to do is asked twice, dry and then for real" do
    First.reset!(answer: { changed: true, lines: [ "moved a row" ] })

    runner = run_with([ First ])

    assert_equal [ true, false ], First.calls
    assert_match(/would:\s+moved a row/, output)
    assert_match(/did:\s+moved a row/, output)
    assert_equal [ First ], runner.changed.map(&:step)
  end

  test "a dry run asks nothing to write, and says only what would happen" do
    First.reset!(answer: { changed: true, lines: [ "moved a row" ] })

    runner = run_with([ First ], dry_run: true)

    assert_equal [ true ], First.calls, "a dry run asked a step to write"
    assert_match(/would:\s+moved a row/, output)
    assert_no_match(/did:/, output)
    assert_equal [ First ], runner.changed.map(&:step)
  end

  test "a failing step stops the run, names itself, and keeps the exception" do
    First.reset!(raises: ActiveRecord::StatementInvalid.new("no such column: scenes.resolved_action"))

    runner = run_with([ First, Second ])

    assert_predicate runner, :failed?
    assert_equal First, runner.failed.step
    assert_match(/FAILED -- ActiveRecord::StatementInvalid: no such column/, output)
    assert_empty Second.calls, "a step after the failure ran anyway"
    assert_not_includes output, "-> second"
  end

  test "a report-only step is asked once, and prints whether or not anything changed" do
    Reporter.reset!(answer: { changed: false, lines: [ "3 stories: 3 healthy" ] })

    runner = run_with([ Reporter ])

    assert_equal [ false ], Reporter.calls
    assert_match(/3 stories: 3 healthy/, output)
    assert_empty runner.changed, "a report-only step counted as a change"
  end

  test "a report-only step is still not asked to write in a dry run" do
    Reporter.reset!(answer: { changed: false, lines: [ "3 stories: 3 healthy" ] })

    run_with([ Reporter ], dry_run: true)

    assert_equal [ true ], Reporter.calls
  end

  # THE GATE. No step in the registry needs a model call and none is expected
  # to, which is exactly why this is tested: the branch has no other reader.
  test "a step that needs a model call is skipped unless it was explicitly allowed" do
    NeedsAModel.reset!(answer: { changed: true, lines: [ "spent a token" ] })

    runner = run_with([ NeedsAModel ])

    assert_empty NeedsAModel.calls, "a step needing a model was run without being allowed to"
    assert_match(/skipped -- it needs a model call/, output)
    assert_match(/ALLOW_MODEL_CALLS=1/, output)
    assert_empty runner.changed
    assert_not runner.failed?, "a skipped step is not a failure"
  end

  test "a step that needs a model call runs when it is explicitly allowed" do
    NeedsAModel.reset!(answer: { changed: true, lines: [ "spent a token" ] })

    run_with([ NeedsAModel ], allow_model_calls: true)

    assert_equal [ true, false ], NeedsAModel.calls
  end

  test "notes are held back when a step had nothing to do, and shown under VERBOSE" do
    First.reset!(answer: { changed: false, notes: [ "two rooms claimed Halkett Rowe" ] })

    run_with([ First ])
    assert_no_match(/Halkett Rowe/, output)

    @out = StringIO.new
    run_with([ First ], verbose: true)
    assert_match(/note: two rooms claimed Halkett Rowe/, output)
  end
end
