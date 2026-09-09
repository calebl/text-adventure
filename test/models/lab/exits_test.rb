require "test_helper"

# THE EXITS LAB'S OWN TABLE: the two picks it is about, and the quantifiers over
# them. `Lab::Exits`'s header is the design.
#
# WHAT THIS FILE IS FOR is the two claims the module makes that a reader would
# otherwise have to take on trust: that the picks are the SAME OBJECTS the
# realization lab reads, so a label added to a closed list arrives in both labs
# with no edit; and that every quantifier means what its words say, including at
# the edges where an answer named nothing.
class Lab::ExitsTest < ActiveSupport::TestCase
  test "the two picks are the realization lab's own, not a second spelling of them" do
    assert_equal %w[inside population], Lab::Exits.picks.map(&:name)

    Lab::Exits.picks.each do |pick|
      assert_same Lab::Realization.pick(pick.name), pick,
                  "#{pick.name} is a copy rather than the pick the other lab reads, so a label added " \
                  "to its closed list would arrive in one lab and not the other"
    end
  end

  test "both picks are answered once per named exit, which is what makes them this lab's subject" do
    assert Lab::Exits.picks.all?(&:per_exit?),
           "a pick that is not per-exit is a fact about the room being written, which is the other lab's"
  end

  test "the closed lists are the ones the schema offers" do
    assert_equal Location::Parameters::INSIDE.keys, Lab::Exits.pick("inside").values
    assert_equal Location::Population::LABELS, Lab::Exits.pick("population").values
  end

  # THE FOUR QUANTIFIERS, EACH AT ITS OWN BOUNDARY. A table of one row per
  # quantifier per interesting count, because the whole of what a quantifier IS is
  # this arithmetic and a header cannot check it.
  test "every quantifier means what its words say" do
    cases = [
      # [ quantifier, insides, named, satisfied ]
      [ "none of them", 0, 3, true ],
      [ "none of them", 1, 3, false ],
      [ "at most one", 0, 3, true ],
      [ "at most one", 1, 3, true ],
      [ "at most one", 2, 3, false ],
      [ "at least one", 0, 3, false ],
      [ "at least one", 1, 3, true ],
      [ "at least one", 3, 3, true ],
      [ "every one", 3, 3, true ],
      [ "every one", 2, 3, false ]
    ]

    cases.each do |name, insides, named, expected|
      quantifier = Lab::Exits.quantifier(name)
      assert_equal expected, quantifier.satisfied_by?(insides: insides, named: named),
                   "#{name.inspect} with #{insides} of #{named} should be #{expected}"
    end
  end

  # THE EDGE THAT WOULD SCORE A FAILURE AS AGREEMENT. An answer that named
  # nothing has every one of nothing given an inside, so `every one` has to refuse
  # it explicitly -- and `none of them` is satisfied by it, which is why
  # `Sample#answered?` and not the quantifier is what keeps such a draw out of the
  # denominator.
  test "every one refuses an answer that named nothing" do
    assert_not Lab::Exits.quantifier("every one").satisfied_by?(insides: 0, named: 0),
               "an answer that named nothing must not read as every one of them being a building"
  end

  # THE BOUNDS ARE WHAT THE BENCH READS, and each of the four words has exactly
  # one of them -- which is what lets `Eval::Realization::Scorer` judge a
  # promoted case's label with one check rather than both, and what
  # `#satisfied_by?` above is derived from rather than written beside.
  test "each quantifier is one-sided, and the every-one floor takes the answer" do
    { "none of them" => [ 0, nil ], "at most one" => [ 1, nil ],
      "at least one" => [ nil, 1 ], "every one" => [ nil, 3 ] }.each do |name, (ceiling, floor)|
      quantifier = Lab::Exits.quantifier(name)

      assert_equal [ ceiling, floor ], [ quantifier.ceiling_over(3), quantifier.floor_over(3) ], name
      assert_equal !ceiling.nil?, quantifier.bounded_above?, name
      assert_equal !floor.nil?, quantifier.bounded_below?, name
    end
  end

  # THE TWO WORDS THE CORPUS'S LABEL USED TO BE, and the mapping is pinned here
  # because it is the whole compatibility story for a stored row and a case
  # written before the captain's Call 6 of 2026-09-08. It is read off what
  # `Eval::Realization::Scorer`'s two checks DID with a boolean: `false` was a
  # ceiling of nought and `true` a floor of one.
  test "the old booleans read as the two quantifiers they always were" do
    assert_equal "none of them", Lab::Exits.quantifier_name(false)
    assert_equal "at least one", Lab::Exits.quantifier_name(true)
    assert_equal Lab::Exits.quantifier("every one"), Lab::Exits.quantifier_for("every one")
  end

  # AND `nil` IS NOT IN THAT TABLE, deliberately: it is *don't care*, which takes
  # a case out of both inside checks' denominators, and mapping it to a word
  # would manufacture a question nobody put.
  test "no label is not a quantifier and a word off the list is not one either" do
    assert_nil Lab::Exits.quantifier_for(nil)
    assert_nil Lab::Exits.quantifier_name(nil)
    assert_nil Lab::Exits.quantifier_for("some of them")
  end

  test "an unknown quantifier is nil rather than a guess" do
    assert_nil Lab::Exits.quantifier("most of them")
    assert_nil Lab::Exits.quantifier(nil)
  end

  # THE SET OF SHAPES `Alignment` REFUSES A ONE-SIDED SET FOR, pinned here because
  # both ends read the constant and a third shape added to it silently changes
  # what the refusal asks for.
  test "the two shapes a well-formed set has to hold are both real quantifiers" do
    assert_equal 2, Lab::Exits::BOTH_SHAPES.size

    Lab::Exits::BOTH_SHAPES.each do |name|
      assert_includes Lab::Exits::QUANTIFIER_NAMES, name
    end
  end

  # IDENTITY, AND IT IS THE REPOSITORY'S ONE ANSWER TO IT. Keyed any narrower and
  # this instrument would file `Causeway Court` and `The Causeway Court` as two
  # places -- the defect `Location::Generator#find_location` was widened to close,
  # reappearing in the tool built to watch for it.
  test "a place is keyed the way the engine keys it" do
    assert_equal WorldSeed.natural_key("The Causeway Court"), Lab::Exits.key_for("Causeway Court")
    assert Lab::Exits.same_place?("The Rust Market", "rust market")
    assert_not Lab::Exits.same_place?("The Rust Market", "The Rust Markets")
  end

  test "two blanks are not one place" do
    assert_not Lab::Exits.same_place?("", nil),
               "a blank key matching a blank key would fold every unnamed thing into one row"
  end

  # THE THRESHOLD IS THE OTHER LAB'S, WHICH IS THE SCOREBOARD'S. A third number
  # would be a third thing to argue about.
  test "the established threshold is shared and not restated" do
    assert_equal Lab::Realization::MIN_DRAWS, Lab::Exits::MIN_DRAWS
    assert_equal Story::Scoreboard::MIN_VERDICTS, Lab::Exits::MIN_DRAWS
  end
end
