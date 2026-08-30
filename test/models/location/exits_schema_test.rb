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

  # Fewer than two and there is no choice to make; more than four and the
  # player is reading a directory rather than a room.
  test "exits is an array bounded at both ends" do
    assert_schema_field(SCHEMA, :exits, type: :array, minItems: 2, maxItems: 4)
  end

  test "every field is described" do
    assert_every_field_described(SCHEMA)
    exit_properties.each_value { |property| assert property["description"].present? }
  end

  test "an exit carries what a stub location and its connection both need" do
    assert_equal %w[name teaser distance time_to_travel travel_method], exit_properties.keys
    assert_equal %w[name teaser distance time_to_travel travel_method],
                 schema_properties(SCHEMA)["exits"]["items"]["required"].map(&:to_s)
  end

  test "every exit field is a bounded string" do
    exit_properties.each do |name, property|
      assert_equal "string", property["type"], "#{name} should be a string"
      assert property["maxLength"].present?, "#{name} needs a maxLength"
    end
  end

  test "forbids fields an exit has nowhere to go" do
    assert_equal false, json_schema_body(SCHEMA)["additionalProperties"]
    assert_equal false, schema_properties(SCHEMA)["exits"]["items"]["additionalProperties"]
  end

  # Two of an exit's fields become a stub Location, the other three become the
  # LocationConnection to it. Nothing generated here has nowhere to be stored.
  test "every exit field maps to a location or connection column" do
    columns = Location.column_names + LocationConnection.column_names

    assert_equal [], exit_properties.keys - columns
  end
end
