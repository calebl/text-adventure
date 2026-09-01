require "test_helper"

# InteractionAgent indexes the response with string keys and interpolates the
# result into the narrator prompt, so the field names here are a hard contract
# with InteractionAgent#narrator_instructions.
class Interaction::SchemaTest < ActiveSupport::TestCase
  include SchemaAssertions

  SCHEMA = Interaction::Schema

  # `inner_resolution` is the sixth, and it is last because it is the one the
  # narrator pass does NOT read: what the character decided is kept on the
  # record (`Interaction#completed?`) rather than handed to the prose.
  FIELDS = %w[pre_thought pre_feeling action post_feeling post_thought inner_resolution].freeze

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

  # The caps are HEADROOM over the shape asked for, not the shape itself. At the
  # old numbers real answers landed exactly on the cap -- a `pre_feeling` of
  # exactly 60 characters ending "hopeful for a (v", a `pre_thought` of exactly
  # 200 -- and the narrator wrote prose over the fragment so nobody could tell.
  test "thoughts and actions have room for the sentence or two they ask for" do
    assert_schema_field(SCHEMA, :inner_resolution, type: :string, maxLength: 320)
    assert_schema_field(SCHEMA, :pre_thought, type: :string, maxLength: 320)
    assert_schema_field(SCHEMA, :action, type: :string, maxLength: 480)
    assert_schema_field(SCHEMA, :post_thought, type: :string, maxLength: 320)
  end

  test "feelings have room for the few words they ask for" do
    assert_schema_field(SCHEMA, :pre_feeling, type: :string, maxLength: 120)
    assert_schema_field(SCHEMA, :post_feeling, type: :string, maxLength: 120)
  end

  # No field may be capped at what its own shape costs: a cap set at the shape
  # does not shorten the answer, it cuts it in half. Narrative English runs
  # ~150 characters to the sentence, so a one-sentence field needs more than
  # that and a two-sentence field more than double.
  test "no field is capped tighter than the shape it asks for" do
    floors = {
      "pre_thought" => 200, "post_thought" => 200, "inner_resolution" => 200,
      "action" => 400, "pre_feeling" => 100, "post_feeling" => 100
    }

    schema_properties(SCHEMA).each do |name, property|
      assert_operator property["maxLength"], :>, floors.fetch(name),
                      "#{SCHEMA}##{name} is capped at what its own shape costs"
    end
  end

  # The truncation guard reads "arrived at the cap" as "was cut off", so the cap
  # the sanitizer checks against has to be the cap the model was actually given.
  # Two numbers here would make the guard fire on the wrong length.
  test "states the same cap to the model as it reports to a caller" do
    schema_properties(SCHEMA).each do |name, property|
      assert_equal property["maxLength"], SCHEMA.max_length_for(name),
                   "#{SCHEMA}##{name}: max_length_for disagrees with the schema"
    end
  end

  # The description is the only place the model reads the budget: the JSON
  # `maxLength` is enforced by truncation, not explained to it. A field whose
  # prose says "one sentence" while its cap says something else is the mismatch
  # this whole change is about.
  test "every field states its character budget, and states the cap it is given" do
    schema_properties(SCHEMA).each do |name, property|
      assert_match(/#{property["maxLength"]} characters/, property["description"],
                   "#{SCHEMA}##{name}'s description must state its own cap")
    end
  end

  test "max_length_for refuses a field this schema does not describe" do
    assert_raises(KeyError) { SCHEMA.max_length_for(:mood) }
  end

  # `action_type` used to be asked for on every turn. `interactions` has no
  # column for it, nothing reads it, and the narrator prompt never saw it -- so
  # it was a decision the model made, paid for, and threw away.
  test "does not ask for fields the interaction record cannot hold" do
    assert_equal [], schema_properties(SCHEMA).keys - Interaction.column_names
  end

  # InteractionAgent reads these five out of the response by name. If a field is
  # renamed here the prompt silently interpolates nil. `inner_resolution` is
  # deliberately absent from the list -- see Interaction::Schema.
  test "carries every field the narrator prompt interpolates" do
    interpolated = %w[pre_thought pre_feeling action post_thought post_feeling]

    assert_equal [], interpolated - schema_properties(SCHEMA).keys
  end
end
