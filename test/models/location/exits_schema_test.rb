require "test_helper"

# The ways out of a location. Each entry becomes a stub Location plus a
# LocationConnection, so the exits are a structured list rather than prose --
# the player has to be able to walk into one.
class Location::ExitsSchemaTest < ActiveSupport::TestCase
  include SchemaAssertions

  SCHEMA = Location::ExitsSchema

  def exit_properties
    schema_properties(SCHEMA)["exits"]["items"]["properties"]
  end

  test "describes exactly the exits list" do
    assert_equal %w[exits], schema_properties(SCHEMA).keys
    assert_equal %w[exits], schema_required(SCHEMA)
  end

  # More than four and the player is reading a directory rather than a room.
  # The floor is one, not two: some places have a single way out, and a floor of
  # two makes the model invent the second.
  test "exits is an array bounded at both ends" do
    assert_schema_field(SCHEMA, :exits, type: :array, minItems: 1, maxItems: 4)
  end

  # A room realized from its neighbour already has its way back, so a dead end
  # can answer with one exit. The opening location has no such neighbour, so an
  # empty array there would be a sealed room -- the floor stays above zero.
  test "one exit is enough and none is not" do
    assert_equal 1, schema_properties(SCHEMA)["exits"]["minItems"]
  end

  test "every field is described" do
    assert_every_field_described(SCHEMA)
    exit_properties.each_value { |property| assert property["description"].present? }
  end

  # FIVE FIELDS, AND THE FIFTH IS A FACT ABOUT THE FAR END. `population` is the
  # word the narrator picks for how populated that place is -- the captain's
  # ruling of 2026-09-07 -- and it is asked here because the count has to be
  # known before that room's OWN detail prompt is built. See
  # `Location::Population`.
  test "an exit carries what a stub location and its connection both need" do
    assert_equal %w[name teaser distance travel_method inside population], exit_properties.keys
    assert_equal %w[name teaser distance travel_method population],
                 schema_properties(SCHEMA)["exits"]["items"]["required"].map(&:to_s)
  end

  # THE ONE OPTIONAL FIELD, and the quietest option is first on its list. An
  # absent pick is a legal answer and means `no inside`, which is what most
  # exits are -- the captain's Call 3 of 2026-09-07, which dissolves the
  # question of which stubs get asked rather than answering it.
  test "the inside pick is optional and offers no inside first" do
    assert_not_includes schema_properties(SCHEMA)["exits"]["items"]["required"].map(&:to_s), "inside"
    assert_equal Location::Parameters::NO_INSIDE, exit_properties["inside"]["enum"].first
    assert_equal Location::Parameters::INSIDE.keys, exit_properties["inside"]["enum"]
  end

  # AND THE POPULATION PICK IS A CLOSED LIST, never a number. A model that could
  # write a number could write four in a room the classifier can only offer three
  # names out of (`Location::Population`).
  #
  # IT IS REQUIRED WHERE `inside` IS NOT, and the difference is that this list has
  # no quietest option: `no inside` is a real answer and there is no word for *I
  # would rather not say*. Nothing rests on the asking either way -- a missing
  # answer leaves the stub with no word and the engine rolls one.
  test "how populated a place is, is one of the engine's own words" do
    assert_equal Location::Population::LABELS, exit_properties["population"]["enum"]
    assert_includes schema_properties(SCHEMA)["exits"]["items"]["required"].map(&:to_s), "population"
  end

  # It follows from the other two, so asking for it was a decision bought that
  # could then contradict the answer it was derived from.
  test "does not ask how long the journey takes" do
    assert_not_includes exit_properties.keys, "time_to_travel"
  end

  test "every exit field is a string bounded by a length or an enum" do
    exit_properties.each do |name, property|
      assert_equal "string", property["type"], "#{name} should be a string"
      assert property["maxLength"].present? || property["enum"].present?,
             "#{name} needs a maxLength or an enum"
    end
  end

  # The two fields that used to be free prose in a 60 character box. That box
  # truncated a real row mid-word, and the prose it held was directional, so
  # the way back recorded the way out. See LocationConnection.
  test "distance and travel method come from LocationConnection's tables" do
    assert_equal LocationConnection::DISTANCES.keys, exit_properties["distance"]["enum"]
    assert_equal LocationConnection::TRAVEL_METHODS.keys, exit_properties["travel_method"]["enum"]
  end

  test "every value the schema can emit is one LocationConnection accepts" do
    connection = build(:location_connection)

    exit_properties["distance"]["enum"].product(exit_properties["travel_method"]["enum"]).each do |distance, method|
      connection.distance = distance
      connection.travel_method = method

      assert connection.valid?, "#{distance} by #{method} is not a connection LocationConnection accepts"
    end
  end

  test "forbids fields an exit has nowhere to go" do
    assert_equal false, json_schema_body(SCHEMA)["additionalProperties"]
    assert_equal false, schema_properties(SCHEMA)["exits"]["items"]["additionalProperties"]
  end

  # Two of an exit's fields become a stub Location, two become the
  # LocationConnection to it, and the fifth becomes the stub's FOOTPRINT.
  # Nothing generated here has nowhere to be stored.
  #
  # `inside` IS A KEY INTO A TABLE AND NOT A COLUMN, which is the captain's rule
  # for every one of these picks -- *the model never writes a free number, only
  # picks from the list* -- so it is named here rather than expected among the
  # column names: `Location::Parameters::INSIDE` holds the band in paces and the
  # engine rolls `width` and `depth` inside it
  # (`Location::Generator#create_stub!`).
  test "every exit field maps to a location or connection column, or to a table that does" do
    columns = Location.column_names + LocationConnection.column_names

    assert_equal [ "inside" ], exit_properties.keys - columns
    assert(Location::Parameters::INSIDE.except(Location::Parameters::NO_INSIDE).values.all? { |band|
      band.min.positive? && band.max >= band.min
    }, "every band is a real span of paces a footprint can be rolled inside")
  end
end
