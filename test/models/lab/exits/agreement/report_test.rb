require "test_helper"
require "rake"

class Lab::Exits::Agreement::ReportTest < ActiveSupport::TestCase
  test "offline task exists and empty sets print no percentage" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("eval:exits_alignment")
    assert Rake::Task.task_defined?("eval:exits_alignment")
    assert_includes printed, "nothing drawn"
    assert_includes printed, "held out"
    assert_includes printed, Story::Scoreboard::MIN_VERDICTS.to_s
    assert_not_includes printed, "%"
  end

  test "unjudged unavailable and below threshold states print denominators and openable disagreements" do
    vantage = create(:lab_exits_vantage)
    suspect = create(:lab_exits_sample, :no_band_picked, vantage: vantage)
    missed = create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)
    vantage.judge!("Tide Flats", verdict: "good")
    vantage.judge!("Salt Chandlery", verdict: "bad", aspects: [ "teaser_wrong" ])
    text = printed
    assert_includes text, "0 of 1 -- not established"
    assert_includes text, "2 judgeable"
    assert_includes text, "0 eligible"
    assert_includes text, "unavailable"
    assert_includes text, "sample ##{suspect.id} /lab/exits/samples/#{suspect.id}"
    assert_includes text, "sample ##{missed.id} /lab/exits/samples/#{missed.id}"
    assert_includes text, "Salt Chandlery -- bad -- teaser_wrong"
    assert_includes text, "No check reads prose"
    assert_not_includes text, "%"
  end

  test "no eligible verdict is distinct from unavailable" do
    create(:lab_exits_sample, :no_band_picked)
    assert_match(/inside_declined\s+no eligible verdict yet \(1 judgeable, 0 eligible\)/, printed)
  end

  test "established tuning and held out stay separate" do
    Story::Scoreboard::MIN_VERDICTS.times do
      vantage = create(:lab_exits_vantage)
      create(:lab_exits_sample, :no_band_picked, vantage: vantage)
      vantage.judge!("Tide Flats", verdict: "bad", aspects: [ "inside_wrong" ])
    end
    held = create(:lab_exits_vantage, world: Eval::HELD_OUT)
    create(:lab_exits_sample, :no_band_picked, vantage: held)
    held.judge!("Tide Flats", verdict: "bad")
    assert_includes printed, "#{Story::Scoreboard::MIN_VERDICTS} of #{Story::Scoreboard::MIN_VERDICTS} (100.0%)"
    assert_includes printed, "#{Eval::HELD_OUT} -- reported apart"
  end

  private

  def printed
    io = StringIO.new
    Lab::Exits::Agreement::Report.new(Lab::Exits::Agreement.sets, io: io).print
    io.string
  end
end
