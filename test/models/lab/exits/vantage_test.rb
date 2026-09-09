require "test_helper"

# A PLACE HE TYPED FOR THE MODEL TO NAME THE WAYS OUT OF.
# `Lab::Exits::Vantage`'s header is the design.
#
# THE TWO THINGS WORTH PINNING are the two that would fail silently: the
# newline-separated `absent` list, because a comma-separated reading of it would
# split a real place name and refuse the whole draw; and `#judge!`'s keying,
# because a judgement filed under a narrower key is a judgement the page cannot
# find.
class Lab::Exits::VantageTest < ActiveSupport::TestCase
  test "a vantage wants a world the lab has a file for" do
    vantage = build(:lab_exits_vantage, world: "Nowhere In Particular")

    assert_not vantage.valid?
    assert_match(/not a world the lab has a file for/, vantage.errors[:world].join)
  end

  test "a vantage wants a name and a teaser" do
    assert_not build(:lab_exits_vantage, name: nil).valid?
    assert_not build(:lab_exits_vantage, teaser: nil).valid?
  end

  # THE COLUMN'S CONTRACT, AND THE REASON IT IS NOT THE OTHER LAB'S. One of the
  # corpus's worlds holds `Grenn's Boarding House, Room 3`; a comma-joined list
  # would make that two names, and `Eval::Realization::Stage` would refuse the
  # draw with a sentence about a room nobody asked for.
  test "the absent list is one place per line, so a place with a comma in it survives" do
    vantage = build(:lab_exits_vantage,
                    absent: "Grenn's Boarding House, Room 3\n  The Long Room  \n\n")

    assert_equal [ "Grenn's Boarding House, Room 3", "The Long Room" ], vantage.absent_names
  end

  test "no absent list is an empty list and not a nil" do
    assert_equal [], build(:lab_exits_vantage).absent_names
  end

  test "a quantifier has to be one the table has a rule for" do
    vantage = build(:lab_exits_vantage, expects_inside_quantifier: "most of them")

    assert_not vantage.valid?
  end

  test "a population expectation may only name a label the model is offered" do
    vantage = build(:lab_exits_vantage, expects_population: "nobody, a legion")

    assert_not vantage.valid?
    assert_match(/not on the list the model picks from/, vantage.errors[:expects_population].join)
  end

  test "an emptied population expectation reads as no expectation rather than an empty set" do
    vantage = create(:lab_exits_vantage, :expecting_an_empty_neighbourhood)
    vantage.declare_population([])

    assert_nil vantage.expects_population_labels,
               "an empty set that allowed nothing would make every draw a miss"
  end

  test "declaring a population expectation takes a list or a string" do
    vantage = build(:lab_exits_vantage)

    vantage.declare_population([ "nobody", "a crowd", "nobody" ])
    assert_equal [ "nobody", "a crowd" ], vantage.expects_population_labels
  end

  # THE KEYING, AND IT IS THE CAPTAIN'S CALL 3. One click has to score every draw
  # that produced that name however the article fell.
  test "a place is judged once however its name is written" do
    vantage = create(:lab_exits_vantage)

    first = vantage.judge!("The Rust Market", expects: { "inside" => [ "a few rooms" ] })
    again = vantage.reload.judge!("rust market", verdict: "good")

    assert_equal first.id, again.id
    assert_equal 1, vantage.reload.judgements.count
  end

  # AND THE TWO HALVES DO NOT CLEAR EACH OTHER, which is what lets one endpoint
  # serve both the typing and the judging.
  test "judging a place keeps an expectation typed for it, and the other way round" do
    vantage = create(:lab_exits_vantage)
    vantage.judge!("The Rust Market", expects: { "inside" => [ "a few rooms" ] })

    judged = vantage.reload.judge!("The Rust Market", verdict: "weak", aspects: [ "band_wrong" ])
    assert_equal [ "a few rooms" ], judged.expects(Lab::Exits.pick("inside"))

    typed = vantage.reload.judge!("The Rust Market", expects: { "inside" => [ "one room" ] })
    assert_equal "weak", typed.verdict
    assert_equal [ "band_wrong" ], typed.aspect_names
  end

  test "a judgement wants a place name" do
    vantage = create(:lab_exits_vantage)

    assert_raises(ArgumentError) { vantage.judge!("   ", verdict: "good") }
  end

  test "the judgement for a name is found by its key and nil when there is none" do
    vantage = create(:lab_exits_vantage)
    vantage.judge!("The Rust Market", verdict: "good")

    assert_equal "rust market", vantage.reload.judgement_for("rust market").name_key
    assert_nil vantage.judgement_for("The Bell Tower")
    assert_nil vantage.judgement_for("")
  end

  # AN EXPECTATION MAY BE EITHER HALF OR A JUDGEMENT'S, so the page can tell a
  # vantage with nothing to score from one with something.
  test "a vantage has an expectation when either half of either shape is declared" do
    assert_not build(:lab_exits_vantage).expectation?
    assert create(:lab_exits_vantage, :expecting_no_insides).expectation?
    assert create(:lab_exits_vantage, :expecting_an_empty_neighbourhood).expectation?

    typed = create(:lab_exits_vantage)
    typed.judge!("The Rust Market", expects: { "inside" => [ "a few rooms" ] })
    assert typed.reload.expectation?
  end

  test "a judged place with no expectation is not an expectation" do
    vantage = create(:lab_exits_vantage)
    vantage.judge!("The Rust Market", verdict: "good")

    assert_not vantage.reload.expectation?
  end

  # THE FIELD THAT IS NOT THERE. A vantage cannot carry an `inside` band, because
  # a laid-out place makes no exits call -- unreachable rather than refused, so
  # this asserts the column's absence rather than a validation.
  test "a vantage has no inside band to cancel its own measurement with" do
    assert_not Lab::Exits::Vantage.column_names.include?("inside"),
               "a vantage with a band would become a building, and a building's ways out are its rooms'"
  end

  test "deleting a vantage takes its draws and its judgements with it" do
    vantage = create(:lab_exits_vantage)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)
    vantage.judge!("The Salt Chandlery", verdict: "good")

    assert_difference [ "Lab::Exits::Sample.count", "Lab::Exits::Judgement.count" ], -1 do
      vantage.destroy!
    end
  end
end
