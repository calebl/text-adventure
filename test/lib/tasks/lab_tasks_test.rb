require "test_helper"
require "rake"

# THE GUARDS IN FRONT OF THE ONE RAKE TASK THAT SPENDS MONEY.
#
# NOTHING HERE DRAWS ANYTHING. `rake lab:realization:draw` makes real model
# calls at a real price, so what is asserted is the refusals -- that a missing
# argument, a nonsense count, an unknown kind and an unconfirmed run each stop
# the task before a call is made -- and the draw loop itself is driven with the
# runner stubbed. A test that bought a sample would be paying to assert a
# printed line (`Lab::SamplesControllerTest`'s rule for its own double).
class LabTasksTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("lab:realization:draw")
    @kind = create(:lab_realization_kind, :a_building)
  end

  test "the task exists in the lab namespace and not in game or eval" do
    assert Rake::Task.task_defined?("lab:realization:draw")
    assert_not Rake::Task.task_defined?("game:lab")
  end

  # BOTH ARGUMENTS ARE REQUIRED AND NEITHER IS DEFAULTED, because a default for
  # either would be this file deciding how much of his money to spend.
  test "it refuses without a kind" do
    error = assert_raises(SystemExit) { with_env("N" => "3") { LabTasks.draw! } }

    assert_match "KIND=<id>", message_of(error)
  end

  test "it refuses without a count" do
    error = assert_raises(SystemExit) { with_env("KIND" => @kind.id.to_s) { LabTasks.draw! } }

    assert_match "N=<count>", message_of(error)
    assert_match Lab::Realization::MIN_DRAWS.to_s, message_of(error),
                 "the sentence says how many draws establish a rate rather than leaving it to be guessed"
  end

  test "it refuses a count that is not a whole number above zero" do
    [ "0", "-2", "some" ].each do |given|
      error = assert_raises(SystemExit) do
        with_env("KIND" => @kind.id.to_s, "N" => given) { LabTasks.draw! }
      end

      assert_match "whole number above zero", message_of(error), "N=#{given} was accepted"
    end
  end

  test "an unknown kind says how to find the right one" do
    error = assert_raises(SystemExit) { with_env("KIND" => "999999", "N" => "1") { LabTasks.draw! } }

    assert_match "rake lab:realization:kinds", message_of(error)
  end

  # THE CONFIRMATION, AND THE ESTIMATE BEFORE IT. The caller sees the price and
  # is then asked; a task that spends on the strength of two environment
  # variables is a task that spends on a typo.
  test "it prints the estimate and then refuses without the confirmation flag" do
    error = nil
    printed = capturing do
      error = assert_raises(SystemExit) { with_env("KIND" => @kind.id.to_s, "N" => "4") { LabTasks.draw! } }
    end

    assert_match "YES=1", message_of(error)
    assert_match "ESTIMATE:", printed
    assert_match "4 draws", printed
    assert_match "detail", printed, "a building makes the detail call alone and the estimate says so"
  end

  # A BUILDING IS PRICED AT ONE CALL AND A ROOM AT TWO
  # (`Location::Generator#write_exits!` returns early once the way in is on a
  # room), so an estimate that priced every kind as a room would overstate the
  # dearer call on every draw.
  test "a room is priced at both calls and a building at one" do
    room = create(:lab_realization_kind)
    printed = capturing do
      assert_raises(SystemExit) { with_env("KIND" => room.id.to_s, "N" => "1") { LabTasks.draw! } }
    end

    assert_match "1 draw x #{Eval::Realization::CALLS.join(" + ")}", printed
    assert_match "#{Eval::Realization::CALLS.size} calls", printed
  end

  # AND IT WILL NOT SPEND AT ALL ABOVE ITS CEILING, however loudly it is
  # confirmed -- `N` is a number a person types, and `N=3000` is one keystroke
  # from `N=300`.
  #
  # DRIVEN THROUGH A PRICED ARM, because `Eval::Cost.price` reads the `models`
  # table and the test database's is empty -- so every real arm here prices at
  # `Eval::Cost::UNKNOWN`, which is zero, and a ceiling test against it would
  # pass whatever the ceiling said. That is `test/factories`' no-dice rule in a
  # different costume: an assertion that cannot fail is worse than none.
  test "it refuses outright above the ceiling" do
    error = nil
    printed = capturing do
      error = assert_raises(SystemExit) { LabTasks.send(:estimate!, @kind, 100_000, priced_arm) }
    end

    assert_match "Lower N", message_of(error)
    assert_match "ESTIMATE:", printed, "the price is printed before the refusal, not instead of it"
  end

  test "an ordinary look at a kind is well inside the ceiling" do
    capturing { LabTasks.send(:estimate!, @kind, Lab::Realization::MIN_DRAWS, priced_arm) }
  end

  # THE LAST GUARD, AND IT IS THE ONE THAT MATTERS MOST IN CI: confirmed, priced
  # and inside the ceiling, it still refuses to draw in the test environment.
  test "it refuses to draw in the test environment even when confirmed" do
    error = assert_raises(SystemExit) do
      capturing { with_env("KIND" => @kind.id.to_s, "N" => "1", "YES" => "1") { LabTasks.draw! } }
    end

    assert_match "must not draw in the test environment", message_of(error)
  end

  # THE DRAWS THEMSELVES, WITH THE RUNNER STUBBED. Each one is stored exactly as
  # a click stores it and the running total is printed as it goes, so an
  # interrupted run has still said what it spent.
  test "each draw is stored like the page stores it and the running cost is printed as it goes" do
    printed = nil

    assert_difference -> { @kind.samples.count }, 3 do
      Lab::Realization::Runner.stub(:new, ->(kind, **) { StubRunner.new(kind) }) do
        printed = capturing { LabTasks.send(:run_draws, @kind, 3, an_arm) }
      end
    end

    assert_match "1/3", printed
    assert_match "3/3", printed
    assert_match "so far", printed
  end

  # A KIND THAT CANNOT BE STAGED STOPS THE RUN, because every remaining draw of
  # it would make the same mistake.
  test "a kind that cannot be staged stops the run rather than repeating the mistake" do
    error = assert_raises(SystemExit) do
      Lab::Realization::Runner.stub(:new, ->(_kind, **) { UnrunnableRunner.new }) do
        capturing { LabTasks.send(:run_draws, @kind, 5, an_arm) }
      end
    end

    assert_match "no place called", message_of(error)
  end

  test "the kinds listing is free and names every kind with its id" do
    printed = capturing { LabTasks.list! }

    assert_match @kind.id.to_s, printed
    assert_match @kind.name, printed
    assert_match @kind.world, printed
  end

  private

  def an_arm = Eval::Classifier::Arm.all([ BaseAgent::REMOTE_MODEL_IDS.first ]).first

  # AN ARM WITH A PRICE ON IT. `Eval::Cost::Price` is the real class at roughly
  # the order of magnitude the shipping model is billed at -- a sample lands in
  # the same fraction of a cent the lab's own page quotes -- so the ceiling is
  # tested against arithmetic and not against zero. A FIXED PRICE AND NOT THE
  # REGISTRY'S, because a registry figure moves when a provider changes its
  # rates and would take these two assertions with it.
  def priced_arm
    Arm.new(id: "a/priced-model",
            price: Eval::Cost::Price.new(model: "a/priced-model",
                                         input_per_million: 0.30, output_per_million: 1.50))
  end

  Arm = Data.define(:id, :price) do
    def local? = false
  end

  # `abort` raises `SystemExit` carrying its sentence, so the sentence is read
  # off the exception rather than off a captured stream.
  def message_of(error) = error.message

  def with_env(values)
    was = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    was.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def capturing
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    captured = $stdout.string
    $stdout = original
    captured
  end

  class StubRunner
    def initialize(kind) = @kind = kind

    def draw!
      @kind.samples.create!(row: { "id" => "lab-kind-#{@kind.id}", "calls" => 1,
                                   "input_tokens" => 1_399, "output_tokens" => 385,
                                   "after" => { "name" => "The Salt House", "rooms" => [] } })
    end
  end

  class UnrunnableRunner
    def draw!
      raise Lab::Realization::Runner::Unrunnable,
            "The Quay House has no place called \"Nowhere At All\""
    end
  end
end
