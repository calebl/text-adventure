require "test_helper"
require "rake"

# WHAT `rake eval:realization_alignment` ACTUALLY PRINTS.
#
# The task is two lines and this is what they produce, so the printer is
# exercised directly and the task is only asserted to exist in the namespace the
# captain asked for. Everything here is offline: the report reads rows already
# stored and makes no call, which is why it can be in the suite at all.
class Lab::Realization::Agreement::ReportTest < ActiveSupport::TestCase
  test "the task exists in the eval namespace and buys nothing" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("eval:realization_alignment")

    assert Rake::Task.task_defined?("eval:realization_alignment")
  end

  # AN EMPTY LAB PRINTS A REPORT AND NOT A CRASH, and it prints no figure at all
  # -- the state the captain will see the first time he runs it.
  test "with nothing drawn it says so for both sets and reports no agreement" do
    printed = report_over(Lab::Realization::Agreement.sets)

    assert_match "SET  #{Lab::Realization::Agreement::TUNING}", printed
    assert_match "SET  #{Lab::Realization::Agreement::HELD_OUT}", printed
    assert_match "nothing drawn", printed
    assert_no_match(/%\)/, printed, "no percentage anywhere with nothing to compute one from")
  end

  # THE HEADING SAYS WHAT AN ELIGIBLE VERDICT IS BEFORE THE FIRST NUMBER, because
  # the number is unreadable without it.
  test "the heading defines an eligible verdict and names the threshold" do
    printed = report_over(Lab::Realization::Agreement.sets)

    assert_match "ELIGIBLE", printed
    assert_match Story::Scoreboard::MIN_VERDICTS.to_s, printed
    assert_match "never pooled", printed
  end

  test "a check with nothing to read on is printed unavailable rather than as a figure" do
    kind = create(:lab_realization_kind, :a_building)
    create(:lab_realization_sample, :a_building, kind: kind, verdict: "good")

    printed = report_over(Lab::Realization::Agreement.sets)

    assert_match(/exit_already_reachable\s+unavailable/, printed)
  end

  # THE DISAGREEMENTS CARRY A WAY TO OPEN THEM. A count is a complaint; the page
  # beside it carries the prompt as sent.
  test "a suspect is printed with its sample path and the check that fired" do
    kind = create(:lab_realization_kind, name: "The Fishmonger's Warehouse")
    sample = create(:lab_realization_sample, :a_room, kind: kind, verdict: "good")

    printed = report_over(Lab::Realization::Agreement.sets)

    assert_match "SUSPECTS", printed
    assert_match "sample ##{sample.id} /lab/samples/#{sample.id}", printed
    assert_match "people_short_of_the_pick", printed
    assert_match "The Fishmonger's Warehouse", printed
  end

  test "a missed verdict is printed with its verdict and what was ticked" do
    kind = create(:lab_realization_kind, :a_building)
    sample = create(:lab_realization_sample, :a_building, kind: kind, verdict: "bad")

    printed = report_over(Lab::Realization::Agreement.sets)

    assert_match "MISSED", printed
    assert_match "sample ##{sample.id} /lab/samples/#{sample.id}", printed
    assert_match "no aspect ticked", printed
  end

  # BELOW THE THRESHOLD THE COUNTS ARE PRINTED AND THE PERCENTAGE IS NOT, which
  # is the one thing this instrument must not get wrong.
  test "below the threshold it prints the fraction and refuses the percentage" do
    kind = create(:lab_realization_kind, :a_building)
    3.times { create(:lab_realization_sample, :a_building, kind: kind, verdict: "good") }

    printed = report_over(Lab::Realization::Agreement.sets)

    assert_match "3 of 3 -- not established", printed
    assert_no_match(/100\.0%/, printed)
  end

  test "at the threshold it prints the percentage beside the fraction" do
    kind = create(:lab_realization_kind, :a_building)
    Story::Scoreboard::MIN_VERDICTS.times do
      create(:lab_realization_sample, :a_building, kind: kind, verdict: "good")
    end

    printed = report_over(Lab::Realization::Agreement.sets)

    assert_match "#{Story::Scoreboard::MIN_VERDICTS} of #{Story::Scoreboard::MIN_VERDICTS} (100.0%)", printed
    assert_no_match(/not established.*parameters_the_engine_narrowed/, printed)
  end

  # THE HELD-OUT WORLD IS LABELLED WHEREVER IT IS PRINTED, so a reader cannot
  # take one of its figures for a tuning figure.
  test "the held out set is named and labelled apart" do
    kind = create(:lab_realization_kind, :a_building, world: Eval::HELD_OUT)
    create(:lab_realization_sample, :a_building, kind: kind, verdict: "good")

    printed = report_over(Lab::Realization::Agreement.sets)

    assert_match "SET  #{Lab::Realization::Agreement::HELD_OUT}", printed
    assert_match Eval::HELD_OUT, printed
    assert_match "never pooled with the tuning worlds", printed
  end

  test "the prose verdicts are reported and said not to be an agreement figure" do
    kind = create(:lab_realization_kind)
    create(:lab_realization_sample, :a_room, kind: kind, verdict: "bad", aspects: "prose")

    printed = report_over(Lab::Realization::Agreement.sets)

    assert_match "PROSE -- kept, reported, never scored", printed
    assert_match "not an agreement figure", printed
  end

  private

  def report_over(sets)
    io = StringIO.new
    Lab::Realization::Agreement::Report.new(sets, io: io).print
    io.string
  end
end
