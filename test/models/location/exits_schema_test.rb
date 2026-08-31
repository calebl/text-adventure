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

  test "an exit carries what a stub location and its connection both need" do
    assert_equal %w[name teaser distance travel_method], exit_properties.keys
    assert_equal %w[name teaser distance travel_method],
                 schema_properties(SCHEMA)["exits"]["items"]["required"].map(&:to_s)
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

  # Two of an exit's fields become a stub Location, the other two become the
  # LocationConnection to it. Nothing generated here has nowhere to be stored.
  test "every exit field maps to a location or connection column" do
    columns = Location.column_names + LocationConnection.column_names

    assert_equal [], exit_properties.keys - columns
  end
end
