require "test_helper"

# WHAT SORT OF PLACE A ROOM IS AND HOW CLUTTERED: two closed lists a model picks
# from and a table a building's rooms are dealt their words out of. What is
# pinned here is that every word is one the engine has, that nil is a state a
# row may be in, and that the deal is a rule about where a room is in its
# building and not a roll.
class Location::KindTest < ActiveSupport::TestCase
  include SchemaAssertions

  def setup
    @story = create(:story)
  end

  test "the lists are what a row may carry, and nothing else is" do
    Location::Kind::KINDS.each { |word| assert_predicate build(:location, story: @story, kind: word), :valid? }
    Location::Kind::DENSITIES.each { |word| assert_predicate build(:location, story: @story, density: word), :valid? }

    assert_not_predicate build(:location, story: @story, kind: "ballroom"), :valid?
    assert_not_predicate build(:location, story: @story, density: "heaving"), :valid?
  end

  # NIL IS NOBODY PICKED, which the opening room and every row older than the
  # columns are honestly in -- so it has to be writable, and nothing is rolled
  # in its place.
  test "no word at all is a valid row" do
    assert_predicate build(:location, story: @story, kind: nil, density: nil), :valid?
  end

  test "the densities run quietest first" do
    assert_equal %w[sparse lived-in cluttered], Location::Kind::DENSITIES
  end

  test "every word a building deals is a sort of room, and every band has one" do
    Location::Kind::TABLE.each do |building, plan|
      bands = plan.values_at("ground", "above", "below")

      assert_empty [ plan.fetch("entry"), *bands.flatten ] - Location::Kind::KINDS, "#{building} deals a word no room may carry"
      assert(bands.none?(&:empty?), "#{building} has a band with nothing to deal")
    end
    assert_equal Location::Kind::TABLE.keys, Location::Kind::BUILDINGS
  end

  # THE ENTRY IS THE BUILDING'S OWN ROOM, and every other room takes the next
  # word of its storey's band in turn.
  test "the room you walk in at is the entry, and the rest are dealt by storey" do
    assert_equal [ "common room", "kitchen", "common room", "kitchen", "sleeping quarters", "sleeping quarters",
                   "storeroom", "storeroom" ],
                 Location::Kind.deal("inn", [ 0, 0, 0, 0, 1, 1, -1, -2 ])
  end

  test "no sort of building, or one the table lacks, deals nothing" do
    assert_equal [ nil, nil, nil ], Location::Kind.deal(nil, [ 0, 0, 1 ])
    assert_equal [ nil ], Location::Kind.deal("cathedral", [ 0 ])
  end

  # NOT A ROLL: the same storeys deal the same words, in any process, for ever.
  test "the deal is the same every time" do
    storeys = [ 0, 0, 1, 1, 1, -1 ]

    assert_equal Location::Kind.deal("fortress", storeys), Location::Kind.deal("fortress", storeys)
  end

  # A SHIP'S STOREYS ARE DECKS: its way in is the airlock, and the decks over and
  # under the one it opens onto are dealt the same way a building's floors are.
  test "a ship is boarded at its airlock and dealt by deck" do
    assert_equal [ "airlock", "corridor", "control room", "machine room" ], Location::Kind.deal("spaceship", [ 0, 0, 1, -1 ])
  end

  # EVERY WORD NAMES ONE SORT OF PLACE: no word appears twice in a list, and no
  # word of either list is another word of it with something added.
  test "no word in either list is two words for one thing" do
    [ Location::Kind::KINDS, Location::Kind::BUILDINGS ].each do |words|
      assert_equal words, words.uniq
      words.each do |word|
        assert_empty words.reject { |other| other == word }.select { |other| other.split.include?(word) },
                     "#{word} is part of another word on its list"
      end
    end
  end

  # THE PLACE CALL ASKS WHAT SORT OF BUILDING IT IS, from the closed list,
  # optionally and outside `parameters` -- see `Location::PlaceSchema`.
  test "the place call picks a sort of building from the table, and need not" do
    property = schema_properties(Location::PlaceSchema)["place_kind"]

    assert_equal Location::Kind::BUILDINGS, property["enum"]
    assert_predicate property["description"], :present?
    assert_not_includes schema_required(Location::PlaceSchema), "place_kind"
    assert_not_includes schema_properties(Location::PlaceSchema)["parameters"]["properties"].keys, "place_kind"
  end
end
