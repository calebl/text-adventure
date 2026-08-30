require "test_helper"

# InteractionAgent indexes the response with string keys and interpolates the
# result into the narrator prompt, so the field names here are a hard contract
# with InteractionAgent#narrator_instructions.
class Interaction::SchemaTest < ActiveSupport::TestCase
  include SchemaAssertions

  SCHEMA = Interaction::Schema

  FIELDS = %w[pre_thought pre_feeling action action_type post_feeling post_thought].freeze

  test "describes exactly the six interaction fields, in order" do
    assert_equal FIELDS, schema_properties(SCHEMA).keys
  end

  test "every field is required" do
    assert_equal FIELDS, schema_required(SCHEMA)
  end

  test "forbids fields the interaction record has no column for" do
    assert_equal false, json_schema_body(SCHEMA)["additionalProperties"]
  end

  test "every field is described" do
    assert_every_field_described(SCHEMA)
  end

  test "the narrative fields are free-form strings" do
    (FIELDS - [ "action_type" ]).each do |field|
      property = assert_schema_field(SCHEMA, field, type: :string)

      assert_nil property["enum"], "#{field} should not be constrained to an enum"
    end
  end

  test "action_type is constrained to an enum" do
    assert_schema_field(SCHEMA, :action_type, type: :string, enum: %w[physical verbal mental])
  end

  # InteractionAgent reads these five out of the response by name. If a field is
  # renamed here the prompt silently interpolates nil.
  test "carries every field the narrator prompt interpolates" do
    interpolated = %w[pre_thought pre_feeling action post_thought post_feeling]

    assert_equal [], interpolated - schema_properties(SCHEMA).keys
  end

  test "the persisted interaction fields all exist as columns" do
    assert_equal [], (FIELDS - [ "action_type" ]) - Interaction.column_names
  end
end
