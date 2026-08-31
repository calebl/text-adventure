require "test_helper"

# InteractionAgent indexes the response with string keys and interpolates the
# result into the narrator prompt, so the field names here are a hard contract
# with InteractionAgent#narrator_instructions.
class Interaction::SchemaTest < ActiveSupport::TestCase
  include SchemaAssertions

  SCHEMA = Interaction::Schema

  FIELDS = %w[pre_thought pre_feeling action post_feeling post_thought].freeze

  test "describes exactly the five interaction fields, in order" do
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
    FIELDS.each do |field|
      property = assert_schema_field(SCHEMA, field, type: :string)

      assert_nil property["enum"], "#{field} should not be constrained to an enum"
    end
  end

  # This schema runs once per turn of dialogue, so an unbounded field puts no
  # ceiling on what a long conversation costs. It had none until this change.
  test "every field carries an explicit max_length" do
    schema_properties(SCHEMA).each do |name, property|
      assert property["maxLength"].present?, "#{SCHEMA}##{name} needs a max_length"
    end
  end

  # A cap on its own is not the lesson: a model given only a character budget
  # writes to the cap. The description has to state the shape too.
  test "every field states its length in words or sentences" do
    schema_properties(SCHEMA).each do |name, property|
      assert_match(/sentence|word/i, property["description"],
                   "#{SCHEMA}##{name} needs a stated sentence or word count")
    end
  end

  test "thoughts and actions are bounded to a sentence or two" do
    assert_schema_field(SCHEMA, :pre_thought, type: :string, maxLength: 200)
    assert_schema_field(SCHEMA, :action, type: :string, maxLength: 300)
    assert_schema_field(SCHEMA, :post_thought, type: :string, maxLength: 200)
  end

  test "feelings are bounded to a few words" do
    assert_schema_field(SCHEMA, :pre_feeling, type: :string, maxLength: 60)
    assert_schema_field(SCHEMA, :post_feeling, type: :string, maxLength: 60)
  end

  # `action_type` used to be asked for on every turn. `interactions` has no
  # column for it, nothing reads it, and the narrator prompt never saw it -- so
  # it was a decision the model made, paid for, and threw away.
  test "does not ask for fields the interaction record cannot hold" do
    assert_equal [], schema_properties(SCHEMA).keys - Interaction.column_names
  end

  # InteractionAgent reads these five out of the response by name. If a field is
  # renamed here the prompt silently interpolates nil.
  test "carries every field the narrator prompt interpolates" do
    interpolated = %w[pre_thought pre_feeling action post_thought post_feeling]

    assert_equal [], interpolated - schema_properties(SCHEMA).keys
  end
end
