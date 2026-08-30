require "test_helper"

# Names the story's opening location. It creates a stub, so it asks for exactly
# what a stub is -- a name and a one-line teaser -- and nothing more.
class Location::OpeningSchemaTest < ActiveSupport::TestCase
  include SchemaAssertions

  SCHEMA = Location::OpeningSchema

  test "describes exactly the two fields a stub is made of" do
    assert_equal %w[name teaser], schema_properties(SCHEMA).keys
  end

  test "every field is required" do
    assert_equal %w[name teaser], schema_required(SCHEMA)
  end

  test "forbids fields the locations table has no column for" do
    assert_equal false, json_schema_body(SCHEMA)["additionalProperties"]
  end

  test "every field is described" do
    assert_every_field_described(SCHEMA)
  end

  test "name is a bounded string" do
    assert_schema_field(SCHEMA, :name, type: :string, maxLength: 60)
  end

  # A teaser is one line the player reads before choosing. Bounded hard: an
  # unbounded one-liner is exactly the field a strong model answers with an
  # essay.
  test "teaser is a bounded string" do
    assert_schema_field(SCHEMA, :teaser, type: :string, maxLength: 160)
  end

  test "every field maps to a location column" do
    assert_equal [], schema_properties(SCHEMA).keys - Location.column_names
  end

  # Whatever this schema produces is saved immediately as a stub, so it has to
  # be everything a stub is validated on.
  test "fills everything a stub is validated on" do
    assert build(:location, :stub).valid?
  end
end
