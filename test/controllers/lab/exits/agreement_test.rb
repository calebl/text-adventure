require "test_helper"

class Lab::Exits::AgreementControllerTest < ActionDispatch::IntegrationTest
  test "empty agreement reports both sets without percentages" do
    get lab_exits_path
    assert_response :success
    assert_select "#agreement" do |sections|
      assert_includes sections.text, "held out"
      assert_includes sections.text, "nothing drawn"
      assert_not_includes sections.text, "%"
    end
  end

  test "unjudged names and unavailable checks are rendered separately" do
    create(:lab_exits_sample, :no_band_picked)
    get lab_exits_path
    assert_response :success
    assert_select "#agreement" do |sections|
      assert_includes sections.text, "names unjudged"
      assert_includes sections.text, "no verdict yet"
      assert_includes sections.text, "unavailable"
      assert_not_includes sections.text, "%"
    end
  end

  test "below threshold renders suspects misses and both denominators without a percentage" do
    vantage = create(:lab_exits_vantage)
    suspect = create(:lab_exits_sample, :no_band_picked, vantage: vantage)
    missed = create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)
    vantage.judge!("Tide Flats", verdict: "good")
    vantage.judge!("Salt Chandlery", verdict: "bad")
    get lab_exits_path
    assert_response :success
    assert_select "#agreement" do |sections|
      assert_includes sections.text, "0 of 1"
      assert_includes sections.text, "not established"
      assert_includes sections.text, "judgeable"
      assert_includes sections.text, "eligible"
      assert_includes sections.text, "no aspect ticked"
      assert_not_includes sections.text, "%"
      assert_select "a[href=?]", lab_exits_sample_path(suspect), text: "sample ##{suspect.id}"
      assert_select "a[href=?]", lab_exits_sample_path(missed), text: "sample ##{missed.id}"
    end
  end

  test "established agreement renders percentage and held out label" do
    Story::Scoreboard::MIN_VERDICTS.times do
      vantage = create(:lab_exits_vantage)
      create(:lab_exits_sample, :no_band_picked, vantage: vantage)
      vantage.judge!("Tide Flats", verdict: "bad", aspects: [ "inside_wrong" ])
    end
    held = create(:lab_exits_vantage, world: Eval::HELD_OUT)
    create(:lab_exits_sample, :no_band_picked, vantage: held)
    get lab_exits_path
    assert_response :success
    assert_select "#agreement" do |sections|
      assert_includes sections.text, "100.0%"
      assert_includes sections.text, Eval::HELD_OUT
      assert_includes sections.text, "apart, never pooled"
    end
  end

  test "invalid create renders the agreement too" do
    post lab_exits_vantages_path, params: { vantage: { name: "", world: "The Quay House" } }
    assert_response :unprocessable_content
    assert_select "#agreement", 1
  end
end
