require "test_helper"

# The generated character sheet is written straight into Character columns, so
# every field here has to line up with a column and with that column's
# validations. A schema field that drifts produces a record that fails to save
# only after the model call has been paid for.
class Character::BaseSchemaTest < ActiveSupport::TestCase
  include SchemaAssertions

  SCHEMA = Character::BaseSchema

  test "describes exactly the four identity fields, in order" do
    assert_equal %w[fullname nickname age sex], schema_properties(SCHEMA).keys
  end

  test "every field is required" do
    assert_equal %w[fullname nickname age sex], schema_required(SCHEMA)
  end

  test "forbids fields the character sheet has no column for" do
    assert_equal false, json_schema_body(SCHEMA)["additionalProperties"]
  end

  test "describes an object" do
    assert_equal "object", json_schema_body(SCHEMA)["type"]
  end

  test "every field is described" do
    assert_every_field_described(SCHEMA)
  end

  test "fullname is a bounded string" do
    assert_schema_field(SCHEMA, :fullname, type: :string, maxLength: 60)
  end

  test "nickname is a bounded string" do
    assert_schema_field(SCHEMA, :nickname, type: :string, maxLength: 30)
  end

  # Character validates age numericality; the bounds keep the model from
  # generating children, which the rest of the game is not written for.
  test "age is a number bounded to adults" do
    assert_schema_field(SCHEMA, :age, type: :number, minimum: 18, maximum: 120)
  end

  test "sex is constrained to an enum" do
    assert_schema_field(SCHEMA, :sex, type: :string, enum: %w[male female non-binary])
  end

  # The enum values are written into Character#sex, which is an ActiveRecord
  # enum. Anything the schema can emit has to be a value that enum accepts.
  test "every sex the schema can emit is a value Character accepts" do
    emitted = schema_properties(SCHEMA)["sex"]["enum"]

    assert_equal emitted, emitted & Character.sexes.values
  end

  test "every field maps to a character column" do
    assert_equal [], schema_properties(SCHEMA).keys - Character.column_names
  end
end
