require "test_helper"

# The generated character sheet is written straight into Character columns, so
# every field here has to line up with a column and with that column's
# validations. A schema field that drifts produces a record that fails to save
# only after the model call has been paid for.
#
# Every field is also interpolated into Character#interaction_instructions, so
# it is re-sent on every turn of dialogue. The max lengths are the point.
class Character::SchemaTest < ActiveSupport::TestCase
  include SchemaAssertions

  SCHEMA = Character::Schema

  EXPECTED_LENGTHS = {
    "fullname" => 60,
    "nickname" => 30,
    "personality" => 400,
    "appearance" => 400,
    "likes" => 200,
    "dislikes" => 200,
    "fears" => 200,
    "backstory" => 1200
  }.freeze

  test "describes exactly the eight generated fields, in order" do
    assert_equal EXPECTED_LENGTHS.keys, schema_properties(SCHEMA).keys
  end

  test "every field is required" do
    assert_equal EXPECTED_LENGTHS.keys, schema_required(SCHEMA)
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

  test "every field is a string with the documented length cap" do
    EXPECTED_LENGTHS.each do |field, max_length|
      assert_schema_field(SCHEMA, field, type: :string, maxLength: max_length)
    end
  end

  test "no field is left unbounded" do
    unbounded = schema_properties(SCHEMA).reject { |_, property| property["maxLength"].present? }

    assert_empty unbounded.keys, "character fields must be length-capped"
  end

  test "every field states its length in words, sentences or list items" do
    schema_properties(SCHEMA).each do |name, property|
      assert_match(/word|sentence|paragraph|list of/i, property["description"],
                   "#{SCHEMA}##{name} needs a stated length")
    end
  end

  test "every field maps to a character column" do
    assert_equal [], schema_properties(SCHEMA).keys - Character.column_names
  end

  # `race`, `age` and `sex` are decided by Character::Generator and stated in
  # the prompt. Asking the model for them as well made the roll advisory and
  # bought the same decision twice.
  test "does not ask for anything the generator already decided" do
    assert_equal [], %w[race age sex] & schema_properties(SCHEMA).keys
  end

  # Character validates these as present. Everything this schema does not cover
  # is supplied by Character::Generator -- the story it belongs to, plus the
  # race, age and sex it decides itself -- so one call cannot leave a character
  # invalid. If a new validated attribute appears in neither list, it will show
  # up here as an unaccounted name.
  test "everything Character validates comes from this schema or the generator" do
    validated = Character.validators
                         .select { |v| v.is_a?(ActiveModel::Validations::PresenceValidator) }
                         .flat_map(&:attributes).map(&:to_s)

    assert_equal %w[story race age sex], validated - EXPECTED_LENGTHS.keys
  end
end
