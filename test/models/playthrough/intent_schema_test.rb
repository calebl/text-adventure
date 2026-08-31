require "test_helper"

# The schema is a factory because `target` is a closed set decided per turn.
# What is worth pinning is that the set really is closed -- if the enum ever
# widened to free text, `Playthrough::Classifier` would start resolving names
# against records that do not exist and the loop would silently do nothing.
class Playthrough::IntentSchemaTest < ActiveSupport::TestCase
  include SchemaAssertions

  def properties(targets)
    json_schema_body(Playthrough::IntentSchema.for(targets))["properties"]
  end

  test "the intent is one of the five the loop knows about" do
    assert_equal %w[move talk examine take other], properties([])["intent"]["enum"]
    assert_equal Playthrough::IntentSchema::INTENTS, properties([])["intent"]["enum"]
  end

  test "the target is closed over the candidates plus a way to say none of them" do
    enum = properties([ "Ashgate Market", "Maren Vosk" ])["target"]["enum"]

    assert_equal [ "Ashgate Market", "Maren Vosk", "nothing" ], enum
  end

  test "a room with nothing in it and nowhere to go still leaves an answer" do
    assert_equal [ "nothing" ], properties([])["target"]["enum"]
  end

  # JSON Schema enums have to be unique, and a character with no nickname
  # contributes a blank. Both arrive here routinely.
  test "blank and duplicate candidates are dropped" do
    enum = properties([ "Maren Vosk", "Maren Vosk", "", "  ", nil ])["target"]["enum"]

    assert_equal [ "Maren Vosk", "nothing" ], enum
  end

  test "both fields are required, so BaseAgent can tell a half answer from a whole one" do
    schema = Playthrough::IntentSchema.for([ "Ashgate Market" ])

    assert_equal %w[intent target], schema.required_properties.map(&:to_s)
  end
end
