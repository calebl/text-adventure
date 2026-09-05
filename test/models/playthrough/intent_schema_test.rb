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

  test "the intent is one of the seven the loop knows about" do
    assert_equal %w[move talk examine take drop attack other], properties([])["intent"]["enum"]
    assert_equal Playthrough::IntentSchema::INTENTS, properties([])["intent"]["enum"]
  end

  # THE SEVENTH WORD, AND THE ONE THAT IS NOT NEXT. `attack` landed in combat
  # slice 8 and was APPENDED rather than grouped beside `talk`, so every other
  # word keeps the index it had and a movement in the classifier bench's
  # confusion matrix across that slice is the new word and not a reshuffled
  # enum. `throw` is deliberately absent and stays absent: it names two records
  # and this schema holds one `target`.
  test "attack is the last act before other, and throw is not in the enum at all" do
    enum = properties([])["intent"]["enum"]

    assert_equal %w[attack other], enum.last(2)
    assert_not_includes enum, "throw"
    assert_equal Playthrough::IntentSchema::INTENTS.size, enum.size
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

  # `also_named` is the same closed set as `target`, so a line that names two
  # things can say which one the turn is not acting on -- and cannot say it
  # with a name the records do not have.
  test "the second name is closed over exactly the same candidates as the target" do
    properties = properties([ "Ashgate Market", "Maren Vosk" ])

    assert_equal properties["target"]["enum"], properties["also_named"]["enum"]
  end

  # A required field and not an optional one, because `strict` schemas require
  # every property -- and `nothing`, which this enum already has, is how the
  # usual answer is given. An array here would have had to be allowed to come
  # back empty, and an empty required array reads as an OMITTED field to
  # `BaseAgent#missing_schema_keys`, which would fail the commonest call in the
  # app on its commonest answer.
  test "every field is required, so BaseAgent can tell a half answer from a whole one" do
    schema = Playthrough::IntentSchema.for([ "Ashgate Market" ])

    assert_equal %w[intent target also_named], schema.required_properties.map(&:to_s)
    assert_includes properties([ "Ashgate Market" ])["also_named"]["enum"], "nothing"
  end

  test "every field tells the model what to put in it" do
    assert_every_field_described(Playthrough::IntentSchema.for([ "Ashgate Market" ]))
  end
end
