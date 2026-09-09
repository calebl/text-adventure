require "test_helper"

# ONE PLACE, AND BOTH HALVES OF WHAT HE SAYS ABOUT IT.
# `Lab::Exits::Judgement`'s header is the design and the captain's Calls 3 and 4.
#
# THE HALVES MUST NOT OVERLAP, which is the claim this file exists to hold: the
# expectation is scored mechanically by set membership and the verdict is his
# click, and neither reader may touch the other's columns. Everything below is
# either that line or the keying that makes one row findable.
class Lab::Exits::JudgementTest < ActiveSupport::TestCase
  test "a judgement keys its name the way the engine keys a place" do
    judgement = create(:lab_exits_judgement, name: "  The Rust Market  ")

    assert_equal "The Rust Market", judgement.name
    assert_equal WorldSeed.natural_key("The Rust Market"), judgement.name_key
  end

  test "two spellings of one place cannot both be filed against one vantage" do
    vantage = create(:lab_exits_vantage)
    create(:lab_exits_judgement, vantage: vantage, name: "The Salt Chandlery")
    clash = build(:lab_exits_judgement, vantage: vantage, name: "salt chandlery")

    assert_not clash.valid?,
               "two rows for one place would put its expectation and its verdict on different rows"
  end

  test "one place may be judged on two different vantages" do
    first = create(:lab_exits_judgement, name: "The Salt Chandlery")
    second = build(:lab_exits_judgement, name: "The Salt Chandlery")

    assert_not_equal first.vantage_id, second.vantage_id
    assert second.valid?, "a place is judged from a vantage, so the same place seen from elsewhere is its own row"
  end

  test "a judgement wants a name" do
    assert_not build(:lab_exits_judgement, name: "  ").valid?
  end

  # THE EXPECTATION HALF.
  test "an expectation may only name a label the model is offered" do
    judgement = build(:lab_exits_judgement, expects_inside: "a mansion")

    assert_not judgement.valid?
    assert_match(/not on the list the model picks from/, judgement.errors[:expects_inside].join)
  end

  test "an emptied expectation reads as no expectation rather than an empty set" do
    judgement = create(:lab_exits_judgement, :expecting_a_few_rooms)
    judgement.declare(Lab::Exits.pick("inside"), [])

    assert_nil judgement.expects(Lab::Exits.pick("inside")),
               "an empty set that allowed nothing would make every draw a miss"
    assert_not judgement.expectation?
  end

  test "the picks it has declared are the ones it has said anything about" do
    judgement = create(:lab_exits_judgement, :expecting_a_few_rooms)

    assert_equal [ "inside" ], judgement.declared.map(&:name)
    assert judgement.expectation?
  end

  # THE PREDICATE THE PAGE PRINTS A SENTENCE FOR, and the state the captain's
  # Call 4c produces most often: a place he typed that no draw has named yet.
  test "an expectation with no verdict is unmet" do
    assert create(:lab_exits_judgement, :expecting_a_few_rooms).unmet?
    assert_not create(:lab_exits_judgement, :expecting_a_few_rooms, :good).unmet?
    assert_not create(:lab_exits_judgement, :good).unmet?
  end

  # SET MEMBERSHIP AGAINST ONE DRAW'S PICKS FOR THIS PLACE.
  test "a place whose band is in the set is satisfied" do
    judgement = create(:lab_exits_judgement, :expecting_a_few_rooms)
    place = create(:lab_exits_sample, :one_building_and_open_ground).named_places.first

    assert judgement.satisfied_by?(place)
  end

  test "a place whose band is outside the set is not" do
    judgement = create(:lab_exits_judgement, :expecting_no_inside)
    place = create(:lab_exits_sample, :one_building_and_open_ground).named_places.first

    assert_not judgement.satisfied_by?(place)
  end

  test "a declared pick that the draw never picked at all is a miss" do
    judgement = create(:lab_exits_judgement, :expecting_nobody)
    place = create(:lab_exits_sample, :one_building_and_open_ground).named_places.first

    assert_not judgement.satisfied_by?(place),
               "the population word has no quietest option to fall back on, so nothing picked is nothing he asked for"
  end

  test "a judgement with nothing declared is satisfied by anything, because it claims nothing" do
    judgement = create(:lab_exits_judgement)
    place = create(:lab_exits_sample, :one_building_and_open_ground).named_places.first

    assert judgement.satisfied_by?(place)
  end

  # AN ABSENT BAND SATISFIES AN EXPECTATION OF `no inside`, because that is what
  # the place became -- `Location::Parameters`' reading of the silence and not a
  # second one.
  test "a place with no band picked satisfies an expectation of no inside" do
    judgement = create(:lab_exits_judgement, :expecting_no_inside, name: "Tide Flats")
    place = create(:lab_exits_sample, :no_band_picked).named_places.first

    assert judgement.satisfied_by?(place)
  end

  # THE JUDGEMENT HALF.
  test "the aspects are the seven no closed list can state" do
    assert_equal %w[inside_wrong band_wrong population_wrong distance_wrong teaser_wrong name_wrong
                    shouldnt_exist], Lab::Exits::Judgement::ASPECTS
  end

  test "an aspect that belongs to the sample is refused here" do
    judgement = build(:lab_exits_judgement, aspects: "too_many_ways_out")

    assert_not judgement.valid?,
               "an aspect about the SET of ways out is the sample's verdict, not one place's"
  end

  test "a verdict that is not one of the three is refused" do
    assert_not build(:lab_exits_judgement, verdict: "excellent").valid?
  end

  # AND NEITHER HALF CLEARS THE OTHER, which is what lets one endpoint serve both.
  test "recording only a verdict leaves the expectation alone" do
    judgement = create(:lab_exits_judgement, :expecting_a_few_rooms)
    judgement.record!(verdict: "weak", aspects: [ "band_wrong" ])

    assert_equal [ "a few rooms" ], judgement.expects(Lab::Exits.pick("inside"))
    assert_equal "weak", judgement.verdict
  end

  test "recording only an expectation leaves the verdict alone" do
    judgement = create(:lab_exits_judgement, :bad)
    judgement.record!(expects: { "inside" => [ "one room" ] })

    assert_equal "bad", judgement.verdict
    assert_equal [ "inside_wrong", "band_wrong" ], judgement.aspect_names
    assert_equal [ "one room" ], judgement.expects(Lab::Exits.pick("inside"))
  end

  test "recording nothing at all changes nothing" do
    judgement = create(:lab_exits_judgement, :expecting_a_few_rooms, :good)
    judgement.record!

    assert_equal "good", judgement.verdict
    assert_equal [ "a few rooms" ], judgement.expects(Lab::Exits.pick("inside"))
  end
end
