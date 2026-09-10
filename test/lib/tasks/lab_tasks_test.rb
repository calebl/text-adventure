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

  # ------------------------------------------------------------- the exits lab
  #
  # THE SAME GUARDS, SHARED RATHER THAN RE-ARGUED. `#draw_vantage!` reaches
  # `#count_or_abort`, `#refuse_without_confirmation` and
  # `#refuse_without_a_key` unchanged, so what is asserted here is the seam
  # (`VANTAGE=`), the pricing difference (always both calls, because a vantage
  # cannot be a building) and the one line this lab prints that the other does
  # not: whether anything is off the books.

  test "the exits tasks exist in the lab namespace" do
    assert Rake::Task.task_defined?("lab:exits:draw")
    assert Rake::Task.task_defined?("lab:exits:vantages")
  end

  test "the exits draw refuses without a vantage and says how to find one" do
    error = assert_raises(SystemExit) { with_env("N" => "3") { LabTasks.draw_vantage! } }

    assert_match "VANTAGE=<id>", message_of(error)
    assert_match "rake lab:exits:vantages", message_of(error)
  end

  test "an unknown vantage says how to find the right one" do
    error = assert_raises(SystemExit) do
      with_env("VANTAGE" => "999999", "N" => "1") { LabTasks.draw_vantage! }
    end

    assert_match "rake lab:exits:vantages", message_of(error)
  end

  test "the exits draw refuses without a count, sharing the other task's sentence" do
    vantage = create(:lab_exits_vantage)
    error = assert_raises(SystemExit) do
      with_env("VANTAGE" => vantage.id.to_s) { LabTasks.draw_vantage! }
    end

    assert_match "N=<count>", message_of(error)
  end

  # A VANTAGE IS NEVER A BUILDING, so it is always priced at both calls -- there
  # is no cheaper one-call draw to model, and an estimate that offered one would
  # be quoting a draw this lab cannot make.
  test "a vantage is priced at both calls and the estimate says why" do
    vantage = create(:lab_exits_vantage)
    error = nil
    printed = capturing do
      error = assert_raises(SystemExit) do
        with_env("VANTAGE" => vantage.id.to_s, "N" => "4") { LabTasks.draw_vantage! }
      end
    end

    assert_match "YES=1", message_of(error)
    assert_match "ESTIMATE:", printed
    assert_match "4 draws x #{Eval::Realization::CALLS.join(" + ")}", printed
    assert_match "never a building", printed
  end

  test "the exits draw refuses outright above the ceiling" do
    error = nil
    printed = capturing do
      error = assert_raises(SystemExit) { LabTasks.send(:estimate_vantage!, 100_000, priced_arm) }
    end

    assert_match "Lower N", message_of(error)
    assert_match "ESTIMATE:", printed
  end

  test "an ordinary look at a vantage is well inside the ceiling" do
    capturing { LabTasks.send(:estimate_vantage!, Lab::Exits::MIN_DRAWS, priced_arm) }
  end

  test "the exits draw refuses to draw in the test environment even when confirmed" do
    vantage = create(:lab_exits_vantage)
    error = assert_raises(SystemExit) do
      capturing do
        with_env("VANTAGE" => vantage.id.to_s, "N" => "1", "YES" => "1") { LabTasks.draw_vantage! }
      end
    end

    assert_match "must not draw in the test environment", message_of(error)
  end

  # THE HEADLINE IS THE TWO NUMBERS THIS LAB IS ABOUT, so a run says as it goes
  # whether it is buying anything measurable at all.
  test "each vantage draw prints what it named and how much of it reached the world" do
    vantage = create(:lab_exits_vantage)
    printed = nil

    assert_difference -> { vantage.samples.count }, 2 do
      Lab::Exits::Runner.stub(:new, ->(subject, **) { StubVantageRunner.new(subject) }) do
        printed = capturing { LabTasks.send(:run_vantage_draws, vantage, 2, an_arm) }
      end
    end

    assert_match "1/2", printed
    assert_match "2 named", printed
    assert_match "1 reaching", printed
    assert_match "so far", printed
  end

  test "a vantage that cannot be staged stops the run rather than repeating the mistake" do
    vantage = create(:lab_exits_vantage)
    error = assert_raises(SystemExit) do
      Lab::Exits::Runner.stub(:new, ->(_subject, **) { UnrunnableRunner.new }) do
        capturing { LabTasks.send(:run_vantage_draws, vantage, 5, an_arm) }
      end
    end

    assert_match "no place called", message_of(error)
  end

  test "the vantages listing is free and names every vantage with its id" do
    vantage = create(:lab_exits_vantage, :with_places_off_the_books)
    printed = capturing { LabTasks.list_vantages! }

    assert_match vantage.id.to_s, printed
    assert_match vantage.name, printed
    assert_match "2 off the books", printed
  end

  # AND THE LISTING SAYS WHICH VANTAGES WILL MEASURE NOTHING, because a vantage
  # with nothing off the books throws away every pick it makes -- the finding
  # this lab was designed around, printed where he chooses what to spend on.
  test "the listing says nothing off the books in words rather than as a nought" do
    create(:lab_exits_vantage)
    printed = capturing { LabTasks.list_vantages! }

    assert_match "nothing off the books", printed
  end

  test "the vantages listing says where a vantage is typed when there are none" do
    printed = capturing { LabTasks.list_vantages! }

    assert_match "/lab/exits", printed
  end

  # THE WAY OUT OF THE LAB, AND IT IS THE ONE EXITS COMMAND THAT IS FREE: it
  # reads draws already bought and prints a corpus case. It writes nothing,
  # because committing a case moves `Eval::Realization.digest` and puts the tree
  # out of baseline until a set is bought -- a spend decision, and therefore a
  # person's (`Lab::Exits::Promotion`'s header).
  test "the exits promote task exists and prints a case without writing the corpus" do
    vantage = create(:lab_exits_vantage, :with_places_off_the_books, :dangerous,
                     :expecting_a_building, name: "Harbour Steps")
    was = File.read(Eval::Realization::CORPUS)

    assert Rake::Task.task_defined?("lab:exits:promote")
    printed = capturing { with_env("VANTAGE" => vantage.id.to_s) { LabTasks.promote_vantage! } }

    assert_match "- id: exits-harbour-steps", printed
    assert_match "expects_inside: at least one", printed
    assert_match "The Custom House", printed
    assert_match Lab::Exits::Promotion::SHAPE, printed
    assert_match "PASTE THIS UNDER `cases:`", printed
    assert_match "moves the corpus digest", printed
    assert_equal was, File.read(Eval::Realization::CORPUS), "this task prints and never writes"
  end

  # AND THE PREAMBLE CARRIES THE WARNING A READER WOULD OTHERWISE CREDIT TO A
  # PROMPT NOBODY TOUCHED: an `exits-promoted` case is a shape the corpus does
  # not hold, so the first one committed becomes a designated case and moves the
  # PROMPT digest as well (`Eval::Realization::Version`).
  test "the promote preamble says the new shape moves the prompt digest too" do
    vantage = create(:lab_exits_vantage, :dangerous, :expecting_no_insides)
    printed = capturing { with_env("VANTAGE" => vantage.id.to_s) { LabTasks.promote_vantage! } }

    assert_match "IS A SHAPE THE CORPUS DOES NOT HOLD YET", printed
    assert_match "PROMPT", printed
  end

  test "promoting refuses without a vantage and says how to find one" do
    error = assert_raises(SystemExit) { LabTasks.promote_vantage! }

    assert_match "VANTAGE=<id> is the vantage to promote", message_of(error)
    assert_match "rake lab:exits:vantages", message_of(error)
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

  # A DRAW THAT WRITES THE ROW THIS LAB READS, which is the two numbers the
  # headline prints: two places named, one of them opened with a band the engine
  # could use.
  class StubVantageRunner
    def initialize(vantage) = @vantage = vantage

    def draw!
      @vantage.samples.create!(
        row: { "id" => "lab-vantage-#{@vantage.id}", "shape" => "exits", "calls" => 2,
               "input_tokens" => 3_247, "output_tokens" => 529,
               "answers" => { "exits" => { "exits" => [
                 { "name" => "The Salt Chandlery", "inside" => "a few rooms", "population" => "nobody" },
                 { "name" => "The Custom House", "inside" => "one room", "population" => "a crowd" }
               ] } },
               "after" => { "name" => "Harbour Steps", "rooms" => [],
                            "new_places" => [ "The Salt Chandlery" ] } }
      )
    end
  end

  class UnrunnableRunner
    def draw!
      # THE STAGE'S OWN REFUSAL, which is what the runner really raises now that
      # standing a typed stub up is `Eval::Realization::Stage`'s job -- there is
      # no second error class of the runner's to catch.
      raise Eval::Realization::Stage::Unstageable,
            "The Quay House has no place called \"Nowhere At All\""
    end
  end
end
