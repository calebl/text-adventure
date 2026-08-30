require "test_helper"

# What realizing a stub writes into Location#description and Location#lore --
# the two columns a realized location is validated on. A field that drifts here
# produces a location that fails to save after the model call has been paid for.
class Location::DetailSchemaTest < ActiveSupport::TestCase
  include SchemaAssertions

  SCHEMA = Location::DetailSchema

  test "describes exactly the two fields a realized location needs" do
    assert_equal %w[description lore], schema_properties(SCHEMA).keys
  end

  test "every field is required" do
    assert_equal %w[description lore], schema_required(SCHEMA)
  end

  test "forbids fields the locations table has no column for" do
    assert_equal false, json_schema_body(SCHEMA)["additionalProperties"]
  end

  test "every field is described" do
    assert_every_field_described(SCHEMA)
  end

  # Both are interpolated into every scene generated in this location, so an
  # unbounded field costs context on every turn spent here.
  test "description is a bounded string" do
    assert_schema_field(SCHEMA, :description, type: :string, maxLength: 1200)
  end

  test "lore is a bounded string" do
    assert_schema_field(SCHEMA, :lore, type: :string, maxLength: 900)
  end

  test "every field maps to a location column" do
    assert_equal [], schema_properties(SCHEMA).keys - Location.column_names
  end

  # The two columns Location requires once realized are exactly the two this
  # schema fills, so realizing cannot leave a location invalid.
  test "fills everything a realized location is validated on" do
    location = build(:location, :stub, detail_level: "realized")
    location.valid?

    assert_equal schema_properties(SCHEMA).keys.sort, location.errors.attribute_names.map(&:to_s).sort
  end
end
