require "test_helper"

# What realizing a stub writes into Location#description and Location#lore --
# the two columns a realized location is validated on. A field that drifts here
# produces a location that fails to save after the model call has been paid for.
#
# And `items` and `people`, which are not location columns at all: they are the
# room's furniture and its cast riding on the same call, written by
# `Item::Registry` and `Character::Registry` into rows of their own. They are
# the two fields here that are deliberately OPTIONAL, because a room containing
# nothing and holding nobody is the ordinary case and an empty required array
# reads as an omitted field to `BaseAgent#missing_schema_keys`.
class Location::DetailSchemaTest < ActiveSupport::TestCase
  include SchemaAssertions

  SCHEMA = Location::DetailSchema

  test "describes the two fields a realized location needs, plus what is in it and who" do
    assert_equal %w[description lore items people], schema_properties(SCHEMA).keys
  end

  # Neither `items` nor `people` is among them, and that is the point: a room
  # with nothing in it and nobody in it would otherwise fail its own realization
  # and rotate to another model.
  test "every field a location is validated on is required" do
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
  # A description is written once and never regenerated, so a sentence about what
  # neighbours the place goes permanently wrong the moment WorldMechanic moves
  # the graph. The instruction not to write one has to stay in the schema.
  test "asks for the place itself, not what neighbours it" do
    described = Location::DetailSchema.new.to_json_schema.dig(:schema, :properties, :description, :description)

    assert_match(/THIS place only/, described)
    assert_match(/can move/, described)
  end

  test "description is a bounded string" do
    assert_schema_field(SCHEMA, :description, type: :string, maxLength: 1200)
  end

  test "lore is a bounded string" do
    assert_schema_field(SCHEMA, :lore, type: :string, maxLength: 900)
  end

  test "every prose field maps to a location column" do
    assert_equal [], schema_properties(SCHEMA).keys - Location.column_names - %w[items people]
  end

  # THE BOUND ON ONE ANSWER, and the captain's number: nobody or one is the
  # ordinary case, not a crowd. The bound on the ROOM and on the WORLD is
  # `Character::Registry`'s, read against the records, because a seeded room can
  # already be at one.
  test "people is bounded at what one answer may name" do
    people = schema_properties(SCHEMA)["people"]

    assert_equal "array", people["type"]
    assert_equal Character::Registry::MAX_PER_CALL, people["maxItems"]
    assert_equal 2, Character::Registry::MAX_PER_CALL
  end

  # Race, age and sex are NOT here: `Character::Registry#slots` rolls them and
  # the prompt states them before the model answers, on Character::Generator's
  # rule that asking for a value the prompt just supplied is a decision bought
  # twice.
  test "a person carries the sheet a Character is validated on, and nothing the engine decides" do
    fields = schema_properties(SCHEMA).dig("people", "items", "properties")

    assert_equal %w[fullname nickname appearance personality backstory likes dislikes fears], fields.keys
    assert_equal [], %w[race age sex] & fields.keys
    assert_equal [], Character::Registry::SHEET.map(&:to_s) - fields.keys
  end

  # Shorter than `Character::Schema`'s equivalents, every one of them: this
  # rides on a call that already costs ~670 output tokens, and a person written
  # at full length would be the most expensive thing in a room.
  test "a generated person's sheet is capped shorter than a generated character's" do
    riding = schema_properties(SCHEMA).dig("people", "items", "properties")
    alone = schema_properties(Character::Schema)

    Character::Registry::SHEET.each do |field|
      assert_operator riding.fetch(field.to_s)["maxLength"], :<, alone.fetch(field.to_s)["maxLength"],
                      "#{field} is not shorter than Character::Schema's"
    end
  end

  # The bound on ONE ANSWER, which is not the bound on the room -- that is
  # Item::Registry's, enforced against the records, because a seeded room can
  # already be at it. Same distinction Location::ExitsSchema documents.
  test "items is bounded at what one room may hold" do
    items = schema_properties(SCHEMA)["items"]

    assert_equal "array", items["type"]
    assert_equal Item::Registry::MAX_PER_ROOM, items["maxItems"]
    assert_equal %w[name description readable inscription], items.dig("items", "properties").keys
  end

  test "an item names itself and says what it is, both bounded" do
    fields = schema_properties(SCHEMA).dig("items", "items", "properties")

    assert_equal 60, fields.dig("name", "maxLength")
    assert_equal 400, fields.dig("description", "maxLength")
  end

  # A NOTE IS BORN WITH ITS WORDS or it is born without them, out of the one
  # call that has just described the room it is lying in. `Item::Inscriber` is
  # the later call, and it exists only for the readable thing that arrived here
  # with none.
  test "an item says whether it has writing on it, and what is written" do
    fields = schema_properties(SCHEMA).dig("items", "items", "properties")

    assert_equal "boolean", fields.dig("readable", "type")
    assert_equal "string", fields.dig("inscription", "type")
    assert_equal Item::INSCRIPTION_LIMIT, fields.dig("inscription", "maxLength")
  end

  # `readable` IS REQUIRED AND `inscription` IS NOT, which is the shape that
  # makes the pair honest: most things have nothing written on them, so
  # `readable: false` with no inscription beside it is the ordinary answer.
  test "readable is asked for every thing and an inscription only when there is one" do
    required = json_schema_body(SCHEMA).dig("properties", "items", "items", "required").map(&:to_s)

    assert_includes required, "readable"
    assert_not_includes required, "inscription"
  end

  # The words themselves, not a description of the object -- that is what
  # `description` already holds, and the difference is the whole reason the
  # field exists. `Playthrough::Turn#read_fact` hands this to the narrator
  # verbatim.
  test "an inscription is asked for as the text itself" do
    described = schema_properties(SCHEMA).dig("items", "items", "properties", "inscription", "description")

    assert_match(/exactly as they appear/, described)
    assert_match(/not a description of it/, described)
  end

  # The collision the classifier cannot survive: an item and an exit, or an
  # item and somebody standing here, answering to one word. Item::Registry
  # refuses one after the fact; the schema says so before the call.
  test "tells the model not to name an item after a person or a place" do
    described = schema_properties(SCHEMA).dig("items", "items", "properties", "name", "description")

    assert_match(/Never the name of a person or of a place/, described)
  end

  # The two columns Location requires once realized are exactly the two this
  # schema fills, so realizing cannot leave a location invalid.
  test "fills everything a realized location is validated on" do
    location = build(:location, :stub, detail_level: "realized")
    location.valid?

    assert_equal schema_required(SCHEMA).sort, location.errors.attribute_names.map(&:to_s).sort
  end
end
