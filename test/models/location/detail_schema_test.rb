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
    assert_equal %w[description lore name items people], schema_properties(SCHEMA).keys
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

  # --- the name a room of a place gets ---------------------------------------
  #
  # OPTIONAL, AND THE PROMPT IS WHAT ASKS FOR IT. Only a room of a laid-out
  # place needs one (`Location::Generator#name_instruction`); every other room
  # in the game already has a name a neighbour or a seed file gave it, and
  # leaving the field required would ask all of them to rename themselves.
  test "name is an optional bounded string" do
    assert_schema_field(SCHEMA, :name, type: :string, maxLength: Location::RoomName::LIMIT)
    assert_not_includes schema_required(SCHEMA), "name"
  end

  # ONE NUMBER, so the bound the model is given and the bound the engine checks
  # a proposal against cannot disagree -- `Character::Registry::PERSON_LIMITS`'
  # rule, and `Location::RoomName` is where it is written down.
  test "the name cap is read from the one place that enforces it" do
    assert_equal Location::RoomName::LIMIT,
                 schema_properties(SCHEMA)["name"]["maxLength"]
  end

  # The field reaches every realization and only some rooms are asked to fill
  # it in, so the description has to say that itself.
  test "the name says it is only for a room the instructions ask to name" do
    described = schema_properties(SCHEMA)["name"]["description"]

    assert_match(/ONLY when the instructions/, described)
    assert_match(/Leave this out entirely/, described)
  end

  # THE BOUND ON ONE ANSWER, read off `Location::Population`'s widest band rather
  # than written beside it. The bound on the ROOM and on the WORLD is
  # `Character::Registry`'s, read against the records, because a seeded room can
  # already be at one.
  test "people is bounded at what one answer may name" do
    people = schema_properties(SCHEMA)["people"]

    assert_equal "array", people["type"]
    assert_equal Location::Population::MOST, people["maxItems"]
    assert_equal Character::Registry::MAX_PER_ROOM, Location::Population::MOST
  end

  # --- the one field whose shape is not a constant ----------------------------
  #
  # The captain's ruling of 2026-09-07: the narrator picks how populated a place
  # is from a closed list and the engine rolls the count inside that word's band
  # (`Location::Population`). So the count is known before the call is made, and
  # `people` is a length the answer has to meet rather than a ceiling it may
  # decline.

  test "a count requires exactly that many people" do
    (1..Location::Population::MOST).each do |wanted|
      schema = Location::DetailSchema.for_people(wanted)
      people = schema_properties(schema)["people"]

      assert_equal wanted, people["minItems"], "#{wanted} should be the floor"
      assert_equal wanted, people["maxItems"], "#{wanted} should be the ceiling"
      assert_includes schema_required(schema), "people", "#{wanted} people must arrive"
    end
  end

  # NOUGHT IS THIS CLASS ITSELF, and that is the guard the whole design rests on
  # rather than an optimisation: an empty required array reads as an OMITTED
  # field to `BaseAgent#missing_schema_keys`, so a room the pick called empty
  # would fail its own realization and rotate through the whole model list
  # looking for one that would invent somebody.
  test "nobody is the schema this class already was" do
    assert_same Location::DetailSchema, Location::DetailSchema.for_people(0)
    assert_not_includes schema_required(SCHEMA), "people"
    assert_nil schema_properties(SCHEMA).dig("people", "minItems")
  end

  # EVERYTHING ELSE IS BYTE-IDENTICAL BETWEEN THE SHAPES, which is what keeps a
  # realization bench figure a measurement of one prompt: a variant that quietly
  # reworded a description would make every comparison a comparison of two
  # changes.
  test "no other field differs between one count and another" do
    shapes = (0..Location::Population::MOST).map do |wanted|
      schema_properties(Location::DetailSchema.for_people(wanted)).except("people")
    end

    assert_equal 1, shapes.uniq.size
  end

  # AND A PERSON IS THE SAME PERSON IN EVERY SHAPE: the count changes how many
  # arrive and never what one of them carries.
  test "a person carries the same sheet whatever the count is" do
    sheets = (0..Location::Population::MOST).map do |wanted|
      schema_properties(Location::DetailSchema.for_people(wanted)).dig("people", "items")
    end

    assert_equal 1, sheets.uniq.size
  end

  # AND EVERY SHAPE ANSWERS TO THIS CLASS'S NAME, which is the one field of the
  # payload that is not a declaration: `RubyLLM::Chat#with_schema` instantiates
  # the class and sends `@name` to the provider, and an anonymous class would
  # send the literal "Schema".
  test "every shape is sent under this schema's own name" do
    (0..Location::Population::MOST).each do |wanted|
      assert_equal "Location::DetailSchema", Location::DetailSchema.for_people(wanted).new.to_json_schema[:name]
    end
  end

  # A COUNT NO BAND CAN PRODUCE IS A PROGRAMMING ERROR AND SAYS SO, rather than
  # silently building a schema for a room that cannot exist.
  test "a count past the widest band is refused" do
    assert_raises(KeyError) { Location::DetailSchema.for_people(Location::Population::MOST + 1) }
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
