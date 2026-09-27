require "test_helper"

# THE KEPT VOLITION BASELINE, RE-SCORED FOR FREE FROM ITS OWN FILES.
#
# `rake eval:volition_baseline_summary` prints what this reads. The figures
# pinned here are the ones the set's README reports, so a change to the
# summary that would move a reported number fails here first.
class Eval::VolitionBaselineTest < ActiveSupport::TestCase
  SET = "volition-baseline-20260926".freeze

  setup { @summary = Eval::VolitionProbe::Baseline.summary(SET) }

  test "every call answered and none failed" do
    assert_equal 48, @summary["calls"]
    assert_equal 48, @summary["succeeded"]
    assert_empty @summary["failed"]
  end

  test "the set was measured on the staged rooms the fixture pins today" do
    kept = JSON.parse(Eval::VolitionProbe::ROOT.join(SET, "receipts.json").read)

    assert_equal Digest::SHA256.file(Eval::VolitionProbe::ROOT.join(SET, "requests.json")).hexdigest, kept["requests_sha256"]
    assert_equal Eval::VolitionProbe::ROOMS.read, Eval::VolitionProbe::ROOT.join(SET, "requests.json").read
  end

  test "the headline figures recompute" do
    assert_equal 56, @summary["answers"]
    assert_equal 48, @summary["pressure_crossed"]
    assert_equal({ "give" => 2, "move" => 8, "take" => 8, "wait" => 38 }, @summary["shapes_chosen"])
    assert_in_delta 0.001683864, @summary["receipt_total"], 1e-12
  end

  test "every chosen act is one the room offered" do
    @summary["people"].flat_map { |p| p["reps"] }.each { |rep| assert rep["sentence"], rep.inspect }
  end

  test "a shape is read off each of the offered sentences" do
    assert_equal "wait", Eval::VolitionProbe::Baseline.shape_of("Stay where you are and change nothing.")
    assert_equal "stop_following", Eval::VolitionProbe::Baseline.shape_of("Stay in The Supply Closet when the player leaves.")
    assert_equal "follow", Eval::VolitionProbe::Baseline.shape_of("Accompany Odile Vance when they leave this room.")
  end
end
