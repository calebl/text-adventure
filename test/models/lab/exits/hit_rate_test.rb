require "test_helper"

# HOW OFTEN A VANTAGE'S EXITS CALL PICKED WHAT HE SAID IT SHOULD.
# `Lab::Exits::HitRate`'s header is the design.
#
# EVERY DENOMINATOR IS PINNED HERE, because a denominator is the one thing an
# instrument can get wrong without anybody noticing: a figure over the wrong set
# still prints, still looks like a rate, and is a lie. So each test below either
# names what is IN a denominator or proves what is out of it.
class Lab::Exits::HitRateTest < ActiveSupport::TestCase
  test "a vantage that declared nothing has no figures at all, not figures of nought" do
    vantage = create(:lab_exits_vantage)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)

    assert_empty vantage.hit_rate.figures
    assert_nil vantage.hit_rate.quantifier
    assert_nil vantage.hit_rate.population
  end

  test "a quantifier is scored over the draws that answered" do
    vantage = create(:lab_exits_vantage, :expecting_a_building)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)
    create(:lab_exits_sample, :every_pick_discarded, vantage: vantage)

    figure = vantage.hit_rate.quantifier

    assert_equal 2, figure.answered
    assert_equal 2, figure.hits, "both answers gave a band to at least one place"
    assert_not figure.established?, "two draws is not established and the page has to say so"
  end

  test "a quantifier of none of them is missed by an answer that gave a band" do
    vantage = create(:lab_exits_vantage, :expecting_no_insides)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)

    figure = vantage.hit_rate.quantifier

    assert_equal 0, figure.hits
    assert_equal 1, figure.answered
    assert_equal [ "The Salt Chandlery" ], figure.misses.first.made
  end

  # THE ONE THAT WOULD BE EASY TO GET WRONG: a discarded band is still a band the
  # model PICKED, so the quantifier counts it. The counter-figure is what says it
  # decided nothing, and the two must not be conflated.
  test "the quantifier counts a band the engine discarded, because the model still picked it" do
    vantage = create(:lab_exits_vantage, :expecting_no_insides)
    create(:lab_exits_sample, :every_pick_discarded, vantage: vantage)

    assert_equal 0, vantage.hit_rate.quantifier.hits,
                 "the pick is what he expects of the model; whether the engine could use it is the reach"
  end

  # THE THREE DRAWS THAT ARE OUT OF EVERY DENOMINATOR.
  test "a failed draw, a draw that named nothing and a draw never asked are all out of the denominator" do
    vantage = create(:lab_exits_vantage, :expecting_no_insides)
    create(:lab_exits_sample, :failed, vantage: vantage)
    create(:lab_exits_sample, :named_nothing, vantage: vantage)
    create(:lab_exits_sample, :never_asked, vantage: vantage)

    rate = vantage.hit_rate

    assert_equal 3, rate.drawn
    assert_equal 0, rate.quantifier.answered,
                  "none of these answered the question, so none of them says anything about it"
    assert_not rate.quantifier.judgeable?
  end

  # THE POPULATION WORD: every pick that was made has to be in the set.
  test "a population expectation is missed when one place of two falls outside it" do
    vantage = create(:lab_exits_vantage, :expecting_an_empty_neighbourhood)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)

    figure = vantage.hit_rate.population

    assert_equal 0, figure.hits
    assert_equal [ "a person or two", "nobody" ], figure.misses.first.made
  end

  test "a draw that made no population pick at all is a miss and not a pass" do
    vantage = create(:lab_exits_vantage)
    vantage.declare_population([ "nobody" ])
    vantage.save!
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)

    assert_equal 0, vantage.hit_rate.population.hits
  end

  # THE CAPTAIN'S CALL 4c, AND THE RULE THAT MAKES IT HONEST.
  test "a per-place expectation is scored over the draws that named that place" do
    vantage = create(:lab_exits_vantage)
    vantage.judge!("The Salt Chandlery", expects: { "inside" => [ "a few rooms" ] })
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)
    create(:lab_exits_sample, :every_pick_discarded, vantage: vantage)

    figure = vantage.reload.hit_rate.places.first

    assert_equal 1, figure.answered, "only one of the two draws named that place"
    assert_equal 1, figure.hits
  end

  test "a place he typed that no draw has named is out of the denominator and not a miss" do
    vantage = create(:lab_exits_vantage)
    vantage.judge!("The Bell Tower", expects: { "inside" => [ "a warren of rooms" ] })
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)

    rate = vantage.reload.hit_rate

    assert_equal 0, rate.places.first.answered
    assert_not rate.places.first.judgeable?
    assert_equal [ "The Bell Tower" ], rate.unnamed.map(&:name),
                 "the page has to be able to say WHY there is no figure instead of printing nought"
  end

  test "a per-place expectation matches a place the model named without its article" do
    vantage = create(:lab_exits_vantage)
    vantage.judge!("The Salt Chandlery", expects: { "inside" => [ "a few rooms" ] })
    create(:lab_exits_sample, :named_without_the_article, vantage: vantage)

    figure = vantage.reload.hit_rate.places.first

    assert_equal 1, figure.answered
    assert_equal 1, figure.hits
  end

  # AND THE FIGURE IS LABELLED WITH THE NAME HE TYPED, not the key it was found
  # by: the key is deliberately not a name, and a figure reading "salt chandlery"
  # beside an answer reading "The Salt Chandlery" reads as somewhere else.
  test "a per-place figure is named the way he typed the place" do
    vantage = create(:lab_exits_vantage)
    vantage.judge!("The Salt Chandlery", expects: { "inside" => [ "a few rooms" ] })
    create(:lab_exits_sample, :named_without_the_article, vantage: vantage)

    assert_equal "The Salt Chandlery: inside", vantage.reload.hit_rate.places.first.name
  end

  test "a per-place expectation is missed with the band it actually got on the miss" do
    vantage = create(:lab_exits_vantage)
    vantage.judge!("The Salt Chandlery", expects: { "inside" => [ Location::Parameters::NO_INSIDE ] })
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)

    figure = vantage.reload.hit_rate.places.first

    assert_equal 0, figure.hits
    assert_equal [ "a few rooms" ], figure.misses.first.made
  end

  # THE COUNTER-FIGURE, AND ITS WHOLE POINT: the gap.
  test "the reach counts the bands given and the ones the engine could use" do
    vantage = create(:lab_exits_vantage)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)
    create(:lab_exits_sample, :every_pick_discarded, vantage: vantage)

    reach = vantage.hit_rate.reach

    assert_equal 4, reach.named
    assert_equal 3, reach.given
    assert_equal 1, reach.reaching
    assert_equal 2, reach.discarded
    assert_in_delta 0.25, reach.reaching_share, 0.001
  end

  test "a vantage with nothing drawn has a reach that refuses to be a share" do
    reach = create(:lab_exits_vantage).hit_rate.reach

    assert_not reach.judgeable?
    assert_equal 0.0, reach.reaching_share
  end

  # THE FIGURE THAT IS ADVICE RATHER THAN A SCORE.
  test "two draws that said the same thing are one distinct answer" do
    vantage = create(:lab_exits_vantage)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)

    assert_equal 2, vantage.hit_rate.drawn
    assert_equal 1, vantage.hit_rate.distinct_answers,
                  "thirty draws of a vantage that answers identically buys thirty copies of one answer"
  end

  test "two draws that named different places are two distinct answers" do
    vantage = create(:lab_exits_vantage)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)
    create(:lab_exits_sample, :every_pick_discarded, vantage: vantage)

    assert_equal 2, vantage.hit_rate.distinct_answers
  end

  # HIS TWO TALLIES, KEPT APART. One is about the set of ways out and the other
  # about a particular place, and a combined number would be neither.
  test "the sample verdicts and the place verdicts are two tallies" do
    vantage = create(:lab_exits_vantage)
    create(:lab_exits_sample, :one_building_and_open_ground, :good, vantage: vantage)
    vantage.judge!("The Salt Chandlery", verdict: "bad")

    rate = vantage.reload.hit_rate

    assert_equal({ "good" => 1 }, rate.verdicts)
    assert_equal({ "bad" => 1 }, rate.place_verdicts)
  end

  test "the established threshold is what the fraction is measured against" do
    vantage = create(:lab_exits_vantage, :expecting_a_building)
    Lab::Exits::MIN_DRAWS.times { create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage) }

    figure = vantage.hit_rate.quantifier

    assert figure.established?
    assert_equal "#{Lab::Exits::MIN_DRAWS} of #{Lab::Exits::MIN_DRAWS}", figure.fraction
  end
end
