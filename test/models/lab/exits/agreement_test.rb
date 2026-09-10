require "test_helper"

class Lab::Exits::AgreementTest < ActiveSupport::TestCase
  test "every scorer check and judgement aspect is explicitly filed" do
    agreement = Lab::Exits::Agreement
    assert_equal Eval::Realization.checks.sort,
                 (agreement::AREAS.values.flatten + agreement::GRADED_BY_THE_WHOLE_SAMPLE).uniq.sort
    assert_equal Lab::Exits::Judgement::ASPECTS.sort, agreement::AREAS.keys.sort
  end

  test "aspects narrow denominators and shouldnt exist speaks to every available check" do
    vantage = create(:lab_exits_vantage)
    create(:lab_exits_sample, :no_band_picked, vantage: vantage)
    vantage.judge!("Tide Flats", verdict: "bad", aspects: [ "population_wrong" ])
    assert_equal 0, board.reading(:inside_declined).eligible
    assert_equal 1, board.reading(:inside_declined).judgeable
    assert_equal 1, board.reading(:population_declined).eligible
    vantage.judge!("Tide Flats", verdict: "bad", aspects: [ "inside_wrong" ])
    assert_equal 1, board.reading(:inside_declined).agreed
    assert_equal 0, board.reading(:population_declined).eligible
    vantage.judge!("Tide Flats", verdict: "bad", aspects: [ "shouldnt_exist" ])
    assert_equal 1, board.reading(:population_declined).eligible
  end

  test "a good name is suspect only for its own exits and counts once across repeats" do
    vantage = create(:lab_exits_vantage)
    clean = create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)
    suspect = create(:lab_exits_sample, :no_band_picked, vantage: vantage)
    vantage.judge!("the tide flats", verdict: "good")
    vantage.judge!("Salt Chandlery", verdict: "good")
    reading = board.reading(:inside_declined)
    assert_equal 2, reading.eligible
    assert_equal 1, reading.agreed
    assert_equal 1, reading.on_good
    assert_equal [ suspect ], reading.suspects.map(&:sample)
    assert_not_includes reading.suspects.map(&:sample), clean
    assert_equal "Tide Flats", reading.suspects.first.name
  end

  test "bare and aspect specific weak bad names are misses when no attributable check fired" do
    vantage = create(:lab_exits_vantage)
    sample = create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)
    vantage.judge!("Tide Flats", verdict: "bad")
    vantage.judge!("Salt Chandlery", verdict: "weak", aspects: [ "teaser_wrong" ])
    assert_equal 2, board.missed.size
    assert_equal [ sample ], board.missed.map(&:sample).uniq
    assert_equal 0, board.reading(:inside_declined).eligible
    assert_equal 1, board.prose_verdicts
  end

  test "a flag elsewhere in the draw does not hide a miss on a clean name" do
    vantage = create(:lab_exits_vantage)
    sample = build(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)
    sample.row["answers"]["exits"]["exits"].first.delete("inside")
    sample.save!
    vantage.judge!("Tide Flats", verdict: "bad")
    assert_equal [ "Tide Flats" ], board.missed.map(&:name)
  end

  test "unjudged and never named judgements supply no eligible verdicts" do
    vantage = create(:lab_exits_vantage)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage, verdict: "good")
    vantage.judge!("Never Named", verdict: "bad")
    assert_equal 2, board.unjudged
    assert_empty board.judged
    assert_empty board.missed
    assert board.readings.all? { |reading| reading.eligible.zero? }
  end

  test "failed and unanswered samples have no subjects" do
    %i[failed named_nothing never_asked].each { |trait| create(:lab_exits_sample, trait) }
    assert_empty board.subjects
    assert board.readings.none?(&:available?)
  end

  test "missing records and whole sample checks are unavailable" do
    vantage = create(:lab_exits_vantage)
    sample = build(:lab_exits_sample, :every_pick_discarded, vantage: vantage)
    sample.row["after"].delete("new_places")
    sample.row["facts"].delete("reachable")
    sample.save!
    vantage.judge!("The Custom House", verdict: "good")
    assert_not board.reading(:inside_on_a_place_that_already_exists).available?
    assert_not board.reading(:exit_already_reachable).available?
    assert board.reading(:inside_declined).available?
    Lab::Exits::Agreement::GRADED_BY_THE_WHOLE_SAMPLE.each do |code|
      assert_not board.reading(code).available?, code.to_s
    end
  end

  test "reachability exemption reads the whole answer before projecting one name" do
    vantage = create(:lab_exits_vantage)
    sample = build(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)
    sample.row["facts"].merge!("expects_new_ground" => false, "reached_from" => "Tide Flats",
                               "reachable" => [ "Tide Flats" ])
    sample.save!
    vantage.judge!("Tide Flats", verdict: "good")
    assert_equal 1, board.reading(:exit_already_reachable).on_good
    sample.row["answers"]["exits"]["exits"].shift
    sample.save!
    assert_not board.reading(:exit_already_reachable).available?
  end

  test "spelling and discarded picks are attributed canonically without changing scorer comparisons" do
    vantage = create(:lab_exits_vantage)
    sample = build(:lab_exits_sample, :named_without_the_article, vantage: vantage)
    sample.row["facts"]["places"] = [ { "name" => "The Salt Chandlery", "realized" => false } ]
    sample.row["after"]["new_places"] = []
    sample.save!
    vantage.judge!("The Salt Chandlery", verdict: "good")
    assert_equal 1, board.reading(:exit_spelled_a_place_differently).on_good
    assert_equal 1, board.reading(:inside_on_a_place_that_already_exists).on_good
  end

  test "threshold counts distinct name verdicts not draws and held out never tops up tuning" do
    vantage = create(:lab_exits_vantage)
    Story::Scoreboard::MIN_VERDICTS.times do
      create(:lab_exits_sample, :no_band_picked, vantage: vantage)
    end
    vantage.judge!("Tide Flats", verdict: "good")
    assert_equal 1, board.reading(:inside_declined).eligible
    assert_nil board.reading(:inside_declined).percentage

    (Story::Scoreboard::MIN_VERDICTS - 2).times { judged_name }
    held = judged_name(world: Eval::HELD_OUT)
    assert_not board.reading(:inside_declined).established?
    assert_equal 1, Lab::Exits::Agreement.sets.last.reading(:inside_declined).eligible
    held.update!(world: "The Quay House")
    assert board.reading(:inside_declined).established?
    assert_equal Story::Scoreboard::MIN_VERDICTS, board.reading(:inside_declined).eligible
    assert_not_nil board.reading(:inside_declined).percentage
  end

  private

  def board = Lab::Exits::Agreement.sets.first

  def judged_name(world: "The Quay House")
    create(:lab_exits_vantage, world: world).tap do |vantage|
      create(:lab_exits_sample, :no_band_picked, vantage: vantage)
      vantage.judge!("Tide Flats", verdict: "good")
    end
  end
end
