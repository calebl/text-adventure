require "test_helper"

# Every field here is interpolated into Character#interaction_instructions, so
# it is re-sent on every single turn of dialogue. The max lengths are the whole
# point of the class: an unbounded field is a context cost paid forever.
class Character::BackgroundSchemaTest < ActiveSupport::TestCase
  include SchemaAssertions

  SCHEMA = Character::BackgroundSchema

  EXPECTED_LENGTHS = {
    "personality" => 400,
    "appearance" => 400,
    "likes" => 200,
    "dislikes" => 200,
    "fears" => 200,
    "backstory" => 1200
  }.freeze

  test "describes exactly the six background fields, in order" do
    assert_equal EXPECTED_LENGTHS.keys, schema_properties(SCHEMA).keys
  end

  test "every field is required" do
    assert_equal EXPECTED_LENGTHS.keys, schema_required(SCHEMA)
  end

  test "forbids fields the character sheet has no column for" do
    assert_equal false, json_schema_body(SCHEMA)["additionalProperties"]
  end

  test "every field is described" do
    assert_every_field_described(SCHEMA)
  end

  test "every field is a string with the documented length cap" do
    EXPECTED_LENGTHS.each do |field, max_length|
      assert_schema_field(SCHEMA, field, type: :string, maxLength: max_length)
    end
  end

  # This is the guard the class comment is about. A field with no cap costs
  # context on every turn of every conversation the character is in.
  test "no field is left unbounded" do
    unbounded = schema_properties(SCHEMA).reject { |_, property| property["maxLength"].present? }

    assert_empty unbounded.keys, "background fields must be length-capped"
  end

  test "every field maps to a character column" do
    assert_equal [], schema_properties(SCHEMA).keys - Character.column_names
  end

  # Character validates all six as present, so the schema must require all six.
  test "covers every background attribute Character validates as present" do
    validated = Character.validators
                         .select { |v| v.is_a?(ActiveModel::Validations::PresenceValidator) }
                         .flat_map(&:attributes).map(&:to_s)

    assert_equal [], EXPECTED_LENGTHS.keys - validated
  end

  test "does not overlap with the base identity schema" do
    overlap = schema_properties(SCHEMA).keys & schema_properties(Character::BaseSchema).keys

    assert_empty overlap
  end
end
