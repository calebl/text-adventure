require "test_helper"

# ONE DRAW, AND THE READING OF AN EXITS ANSWER THIS WHOLE LAB STANDS ON.
# `Lab::Exits::Sample`'s header is the design.
#
# THE CLAIM WORTH PINNING HARDEST is `#insides_reaching`. It is the difference
# between the figure the bench already prints and the one the captain asked for
# in Call 5, and it is read off `after["new_places"]` -- the RECORD of what the
# world gained -- rather than off the answer. A reading that took the answer's
# word for it would credit a band the engine threw away, which is exactly the
# defect this lab was designed around.
class Lab::Exits::SampleTest < ActiveSupport::TestCase
  test "a draw that answered names every place with its picks" do
    sample = create(:lab_exits_sample, :one_building_and_open_ground)

    assert sample.answered?
    assert_equal [ "The Salt Chandlery", "Tide Flats" ], sample.named_places.map(&:name)
    assert_equal [ "a few rooms", Location::Parameters::NO_INSIDE ], sample.named_places.map(&:band)
    assert_equal [ "a person or two", "nobody" ], sample.named_places.map(&:population)
    assert_equal [ "a short walk", "a short walk" ], sample.named_places.map(&:distance)
  end

  test "an inside is a band that is not no inside" do
    sample = create(:lab_exits_sample, :one_building_and_open_ground)

    assert_equal [ "The Salt Chandlery" ], sample.insides_given.map(&:name)
  end

  # THE COUNTER-FIGURE'S NUMERATOR, and the reason this lab exists.
  test "a band on a place the engine actually opened is reaching" do
    sample = create(:lab_exits_sample, :one_building_and_open_ground)

    assert_equal [ "The Salt Chandlery" ], sample.insides_reaching.map(&:name)
    assert sample.named_places.all?(&:new_place?)
  end

  test "a band on a place the world already held is given and never reaching" do
    sample = create(:lab_exits_sample, :every_pick_discarded)

    assert_equal 2, sample.insides_given.size
    assert_empty sample.insides_reaching,
                 "connect_exit! hands a band to create_stub! only for a place that does not exist, so " \
                 "a band on one that does decided nothing"
    assert sample.named_places.none?(&:new_place?)
  end

  # THE KEYING AGAIN, FROM THE OTHER SIDE: the engine opened the place under the
  # name the model gave, and the reading has to recognise it however the article
  # fell -- because `#find_location` resolves the same way.
  test "a place opened without its article is still recognised as opened" do
    sample = create(:lab_exits_sample, :named_without_the_article)

    assert_equal [ "Salt Chandlery" ], sample.insides_reaching.map(&:name)
    assert_equal Lab::Exits.key_for("The Salt Chandlery"), sample.named_places.first.key
  end

  # AN ABSENT BAND IS NOT `no inside`, and both readings matter: the place became
  # open ground either way, but one is a decision and the other is a decision NOT
  # MADE.
  test "an absent band reads as the quietest option and as no pick made" do
    place = create(:lab_exits_sample, :no_band_picked).named_places.first

    assert_not place.pick_made?
    assert_not place.inside?
    assert_equal Location::Parameters::NO_INSIDE, place.band,
                 "the place became open ground, which is what Location::Parameters made of the silence"
  end

  # THE DENOMINATOR'S GATE, IN ALL THREE OF ITS STATES. Each of these would
  # otherwise be scored as an answer, and `none of them` would read as satisfied
  # by every one of them.
  test "a failed draw answered nothing" do
    sample = create(:lab_exits_sample, :failed)

    assert sample.failed?
    assert_not sample.answered?
    assert_empty sample.named_places
  end

  test "a draw that named nothing answered nothing" do
    assert_not create(:lab_exits_sample, :named_nothing).answered?
  end

  test "a draw whose exits call was never made answered nothing" do
    assert_not create(:lab_exits_sample, :never_asked).answered?
  end

  # HIS VERDICT IS ABOUT THE SET, and the aspects are the ones only the set can be
  # wrong about.
  test "the aspects are about the set of ways out and nothing else" do
    assert_equal %w[too_many_ways_out too_few_ways_out invented_a_way_out no_reason_to_prefer
                    not_this_place], Lab::Exits::Sample::ASPECTS
  end

  test "an aspect that is not one is refused with the list" do
    sample = build(:lab_exits_sample, aspects: "inside_wrong")

    assert_not sample.valid?
    assert_match(/which is not one of/, sample.errors[:aspects].join)
  end

  test "a verdict that is not one of the three is refused" do
    assert_not build(:lab_exits_sample, verdict: "excellent").valid?
  end

  test "the ladder is the play page's and not a second one" do
    assert_equal Playthrough::Feedback::VERDICTS, Lab::Exits::Sample::VERDICTS
  end

  # AMENDMENT, AND ITS ONE RULE: a changed verdict does not silently throw away
  # which parts he had already said were wrong, and an empty list is how they are
  # cleared.
  test "recording a verdict without aspects leaves the aspects alone" do
    sample = create(:lab_exits_sample, :one_building_and_open_ground, :bad)
    sample.record!(verdict: "weak")

    assert_equal "weak", sample.verdict
    assert_equal [ "too_many_ways_out", "invented_a_way_out" ], sample.aspect_names
  end

  test "an empty list of aspects clears them" do
    sample = create(:lab_exits_sample, :one_building_and_open_ground, :bad)
    sample.record!(verdict: "good", aspects: [])

    assert_empty sample.aspect_names
  end

  test "a blank verdict clears it" do
    sample = create(:lab_exits_sample, :one_building_and_open_ground, :good)
    sample.record!(verdict: "")

    assert_not sample.verdict?
  end

  # THE ROW IS READ THROUGH THE BENCH'S OWN OBJECT, so the page cannot come to a
  # different reading of a draw from the one the bench would.
  test "the reading is the bench's and the flags are the scorer's" do
    sample = create(:lab_exits_sample, :one_building_and_open_ground)

    assert_kind_of Eval::Realization::Scorer::Reading, sample.reading
    assert_kind_of Array, sample.flags
  end

  test "a row read back out of the json column reads the same as one written in process" do
    sample = create(:lab_exits_sample, :one_building_and_open_ground)

    assert_equal sample.named_places.map(&:name),
                 Lab::Exits::Sample.find(sample.id).named_places.map(&:name)
  end
end
