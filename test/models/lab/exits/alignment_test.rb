require "test_helper"

# THE REFUSAL, AND THE ONE FIGURE THAT SURVIVES IT.
# `Lab::Exits::Alignment`'s header is the design and the captain's Call 5.
#
# WHAT THIS FILE HOLDS is that a one-sided set gets no figure at all. It is the
# only guard against the dominant strategy the exits prompt itself invites --
# *"say NO INSIDE for almost all of them"* -- and a guard that silently stopped
# guarding would leave the instrument reading full marks for a model that had
# emptied the game of buildings. That is not hypothetical: the
# `interior-entry-before` stored set is that model, measured.
class Lab::Exits::AlignmentTest < ActiveSupport::TestCase
  test "a set of nothing but none of them vantages gets no figure and a reason" do
    vantage = create(:lab_exits_vantage, :expecting_no_insides)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)

    alignment = Lab::Exits::Alignment.new([ vantage ])

    assert_nil alignment.figure
    assert_not alignment.both_shapes?
    assert_equal [ "at least one" ], alignment.missing
    assert_match(/satisfied by a model that never picks a building/, alignment.refusal.to_s)
  end

  test "a set of nothing but at least one vantages is refused the other way round" do
    vantage = create(:lab_exits_vantage, :expecting_a_building)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)

    alignment = Lab::Exits::Alignment.new([ vantage ])

    assert_nil alignment.figure
    assert_equal [ "none of them" ], alignment.missing
  end

  test "a two-sided set gets a figure pooled over draws" do
    open_country = create(:lab_exits_vantage, :expecting_no_insides)
    a_lane = create(:lab_exits_vantage, :expecting_a_building)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: open_country)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: a_lane)

    alignment = Lab::Exits::Alignment.new([ open_country, a_lane ])

    assert alignment.both_shapes?
    assert_nil alignment.refusal
    assert_equal 2, alignment.figure.answered
    assert_equal 1, alignment.figure.hits, "the lane was satisfied and the open country was not"
  end

  # POOLED AND NOT AVERAGED, which is the difference between an honest figure and
  # one that lets a vantage drawn twice outvote a vantage drawn thirty times.
  test "a vantage with more draws weighs more than one with fewer" do
    open_country = create(:lab_exits_vantage, :expecting_no_insides)
    a_lane = create(:lab_exits_vantage, :expecting_a_building)
    3.times { create(:lab_exits_sample, :one_building_and_open_ground, vantage: a_lane) }
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: open_country)

    figure = Lab::Exits::Alignment.new([ open_country, a_lane ]).figure

    assert_equal 4, figure.answered
    assert_equal 3, figure.hits
  end

  # THE REFUSAL IS ABOUT THE EXPECTATIONS AND NOT ABOUT THE ANSWERS. A set that
  # holds a failing `at least one` vantage is a well-shaped set reporting bad
  # news, which is exactly what it is for.
  test "a shape counts towards the set even when every draw of it misses" do
    open_country = create(:lab_exits_vantage, :expecting_no_insides)
    a_lane = create(:lab_exits_vantage, :expecting_a_building)
    create(:lab_exits_sample, :every_pick_discarded, vantage: open_country)
    # A band on a place the world held is still a band picked, so this one hits;
    # what makes the point is that the shape is counted from the EXPECTATION.
    create(:lab_exits_sample, :no_band_picked, vantage: a_lane)

    alignment = Lab::Exits::Alignment.new([ open_country, a_lane ])

    assert alignment.both_shapes?
    assert_equal 0, alignment.figure.hits
    assert_equal 2, alignment.figure.answered
  end

  # A VANTAGE WITH NO DRAW IS NOT A SHAPE THE SET HOLDS, because a declared
  # expectation nothing has answered says nothing about the prompt.
  test "a declared vantage with nothing drawn does not make the set two-sided" do
    open_country = create(:lab_exits_vantage, :expecting_no_insides)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: open_country)
    undrawn = create(:lab_exits_vantage, :expecting_a_building)

    alignment = Lab::Exits::Alignment.new([ open_country, undrawn ])

    assert_not alignment.both_shapes?
    assert_equal [ open_country ], alignment.scorable
  end

  test "a vantage that declared no quantifier is not scorable at all" do
    vantage = create(:lab_exits_vantage)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)

    assert_empty Lab::Exits::Alignment.new([ vantage ]).scorable
  end

  test "an empty set is refused rather than reported as nought" do
    alignment = Lab::Exits::Alignment.new([])

    assert_nil alignment.figure
    assert_equal Lab::Exits::BOTH_SHAPES, alignment.missing
  end

  # THE COUNTER-FIGURE BELONGS TO THE SET, and it is summed over every vantage
  # rather than over the scorable ones: it is a property of the PROMPT, so a
  # vantage he has not declared anything about still spends its draws on it.
  test "the reach is summed over every vantage, declared or not" do
    declared = create(:lab_exits_vantage, :expecting_no_insides)
    undeclared = create(:lab_exits_vantage)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: declared)
    create(:lab_exits_sample, :every_pick_discarded, vantage: undeclared)

    reach = Lab::Exits::Alignment.new([ declared, undeclared ]).reach

    assert_equal 4, reach.named
    assert_equal 3, reach.given
    assert_equal 1, reach.reaching
  end
end
