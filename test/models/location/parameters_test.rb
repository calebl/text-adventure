require "test_helper"

# THE CLOSED VOCABULARY A MODEL PICKS A BUILDING OUT OF, and the tables behind
# it. Everything here is arithmetic over constants -- no records, no rolls except
# the seeded footprint -- which is what a "the model never writes a number" rule
# reduces to when it is really kept.
class Location::ParametersTest < ActiveSupport::TestCase
  def picked(**picks) = Location::Parameters.from(picks.transform_keys(&:to_s))

  # --- the defaults, which are what a world looks like when nobody answers ----

  test "an absent block is every quietest option" do
    none = Location::Parameters.none

    assert_equal Location::Parameters::NO_INSIDE, none.inside
    assert_not_predicate none, :inside?
    assert_equal 1, none.above, "one floor and no more"
    assert_equal 0, none.below, "nothing underneath"
    assert_equal Location::SAFE, none.danger
    assert_equal Location::Parameters::FLAT, none.gradient
    assert_equal Location::Parameters::NO_HAZARD, none.hazard
    assert_not_predicate none, :hazard?
  end

  test "nil, a nil field and a label outside the list all fall to the quietest option" do
    [ Location::Parameters.from(nil), picked(danger: nil), picked(danger: "apocalyptic") ].each do |parameters|
      assert_equal Location::SAFE, parameters.danger
    end
  end

  # `deadly` IS A SEED FILE'S WORD -- `Location::DANGERS`' own rule. A model
  # cannot pick it out of the schema and cannot get it past this either.
  test "deadly is not a danger a building may be picked as" do
    assert_not_includes Location::Parameters::DANGER.keys, "deadly"
    assert_equal Location::SAFE, picked(danger: "deadly").danger
  end

  test "every danger a building may be born with is one Location accepts" do
    Location::Parameters::DANGER.values.flatten.uniq.each do |danger|
      assert_includes Location::DANGERS.keys, danger
    end
  end

  test "every hazard a building may be picked as is one Location accepts" do
    (Location::Parameters::HAZARDS - [ Location::Parameters::NO_HAZARD ]).each do |hazard|
      assert_includes Location::HAZARDS.keys, hazard
    end
  end

  # --- the footprint ----------------------------------------------------------

  test "no inside asks for no footprint at all" do
    assert_nil Location::Parameters.none.footprint(Random.new(1))
  end

  # THE BAND IS THE WHOLE OF WHAT A LABEL MEANS, and the two sides are rolled
  # inside it independently -- `Location::Interior::FOOTPRINT_SIDES`' shape, so a
  # building is not a square unless the dice say so.
  test "each band rolls a footprint inside itself" do
    Location::Parameters::INSIDE.except(Location::Parameters::NO_INSIDE).each do |label, band|
      20.times do |seed|
        sides = picked(inside: label).footprint(Random.new(seed))

        assert_equal 2, sides.size
        sides.each { |side| assert_includes band, side, "#{label} rolled #{side} outside #{band}" }
      end
    end
  end

  test "a footprint is re-derivable from the same seed and moves with a different one" do
    band = picked(inside: "a few rooms")

    assert_equal band.footprint(Random.new(7)), band.footprint(Random.new(7))
    rolled = (1..40).map { |seed| band.footprint(Random.new(seed)) }.uniq

    assert_operator rolled.size, :>, 1, "every seed rolled the same footprint, so nothing is being drawn"
  end

  # A band whose smaller side cannot hold `MINIMUM_SIDE` would be a building
  # laid out as one room whatever it asked for, which is the narrowing
  # `Eval::Realization::Scorer` reports rather than something to allow by
  # accident.
  test "every band is wide enough for a room" do
    Location::Parameters::INSIDE.except(Location::Parameters::NO_INSIDE).each_value do |band|
      assert_operator band.min, :>=, Location::Interior::MINIMUM_SIDE
    end
  end

  # --- the gradient, which is the same slope said about two columns -----------

  test "a flat building leans nowhere" do
    flat = picked(danger: "uneasy", hazard: "unlit")

    [ -2, -1, 0, 1, 2 ].each do |storey|
      assert_equal Location::Parameters::DANGER.fetch("uneasy"), flat.danger_for(storey)
      assert_equal Location::Parameters::HAZARD_SHARE, flat.hazard_share_for(storey)
    end
  end

  # WORSE THE DEEPER YOU GO: a room below the ground floor draws from a worse
  # list than one on it, and a room above draws from a quieter one.
  test "a building that gets worse downward leans down" do
    deep = picked(danger: "uneasy", gradient: "worse the deeper you go")

    assert_equal Location::Parameters::DANGER.fetch("dangerous"), deep.danger_for(-1)
    assert_equal Location::Parameters::DANGER.fetch("uneasy"), deep.danger_for(0)
    assert_equal Location::Parameters::DANGER.fetch(Location::SAFE), deep.danger_for(2)
  end

  test "a building that gets worse upward leans the other way" do
    tower = picked(danger: "uneasy", gradient: "worse the higher you climb")

    assert_equal Location::Parameters::DANGER.fetch(Location::SAFE), tower.danger_for(-1)
    assert_equal Location::Parameters::DANGER.fetch("dangerous"), tower.danger_for(2)
  end

  # ONE RUNG AND NOT ONE PER FLOOR. The ladder has three rungs, so a five-storey
  # building would otherwise spend the whole of it on the second floor.
  test "the lean is one rung however many floors away it is" do
    deep = picked(danger: "uneasy", gradient: "worse the deeper you go")

    assert_equal deep.danger_for(-1), deep.danger_for(-4)
  end

  test "the lean never falls off either end of the ladder" do
    Location::Parameters::GRADIENT.each_key do |gradient|
      Location::Parameters::DANGER.each_key do |danger|
        [ -3, 0, 3 ].each do |storey|
          list = picked(danger: danger, gradient: gradient).danger_for(storey)

          assert_includes Location::Parameters::DANGER.values, list
        end
      end
    end
  end

  # --- the hazard, which is a RATE and never an assignment ---------------------

  test "a building with no hazard throws no die on any storey" do
    quiet = picked(danger: "dangerous", gradient: "worse the deeper you go")

    [ -2, 0, 2 ].each { |storey| assert_equal 0, quiet.hazard_share_for(storey) }
  end

  # THE SHARE IS WHAT KEEPS A DEEP AIRLESS WARREN SURVIVABLE: `silent` and
  # `airless` are charged every turn, so a share of the whole die would be a
  # building that ends a playthrough by arithmetic.
  test "a hazardous building hazards a share of its rooms and never all of them" do
    Location::Parameters::GRADIENT.each_key do |gradient|
      airless = picked(hazard: "airless", danger: "dangerous", gradient: gradient)

      [ -3, -1, 0, 1, 3 ].each do |storey|
        share = airless.hazard_share_for(storey)

        assert_operator share, :>, 0
        assert_operator share, :<, Location::Parameters::HAZARD_DIE,
                        "every room of storey #{storey} would carry it"
      end
    end
  end

  # AND THE GRADIENT REACHES THE HAZARD EVEN WHERE IT CANNOT REACH THE DANGER,
  # which is the whole of why the captain's Call 1 of 2026-09-07 rescues the
  # gradient: a building already at the top of the danger ladder cannot get any
  # more dangerous, and its cellar can still be the part that takes hit points.
  test "the deepest floor of an already dangerous building is hazarded more often" do
    deep = picked(danger: "dangerous", gradient: "worse the deeper you go", hazard: "flooded")

    assert_equal deep.danger_for(0), deep.danger_for(-2), "the ladder is already at its top"
    assert_operator deep.hazard_share_for(-2), :>, deep.hazard_share_for(0)
  end
end
