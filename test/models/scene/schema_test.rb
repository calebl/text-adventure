require "test_helper"

# What arriving somewhere writes into a Scene. `description` is validated on
# the record, so a field that drifts here produces a scene that fails to save
# after the model call has already been paid for.
class Scene::SchemaTest < ActiveSupport::TestCase
  include SchemaAssertions

  SCHEMA = Scene::Schema

  test "describes exactly the two fields an arrival writes" do
    assert_equal %w[description summary], schema_properties(SCHEMA).keys
  end

  test "every field is required" do
    assert_equal %w[description summary], schema_required(SCHEMA)
  end

  test "forbids fields the scenes table has no column for" do
    assert_equal false, json_schema_body(SCHEMA)["additionalProperties"]
  end

  test "every field is described" do
    assert_every_field_described(SCHEMA)
  end

  test "every field maps to a scene column" do
    assert_equal [], schema_properties(SCHEMA).keys - Scene.column_names
  end

  # Shorter than Location::DetailSchema#description (1,200) on purpose: the
  # room's own description is already in the prompt and already in front of the
  # player, so an arrival that runs as long is describing the room twice.
  test "the description is bounded, and more tightly than the room's" do
    assert_schema_field(SCHEMA, :description, type: :string, maxLength: 900)

    assert_operator schema_properties(SCHEMA)["description"]["maxLength"],
                    :<,
                    schema_properties(Location::DetailSchema)["description"]["maxLength"]
  end

  # This is the field long playthroughs will be summarised from, so it has to
  # stay small enough that a run of them is cheaper than the prose they replace.
  test "the summary is bounded to one sentence" do
    assert_schema_field(SCHEMA, :summary, type: :string, maxLength: 200)
  end

  test "the description covers what a scene is validated on" do
    scene = build(:scene, description: nil, summary: nil)
    scene.valid?

    assert_includes schema_properties(SCHEMA).keys, "description"
    assert_includes scene.errors.attribute_names.map(&:to_s), "description"
  end
end
