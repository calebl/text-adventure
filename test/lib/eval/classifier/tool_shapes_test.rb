require "test_helper"

# THE TWO TOOL-CALL SHAPES, OFFLINE -- no model, no key, no network. Shape B is
# tested against the real gem's own payload renderer so the closed-set claim
# in `data/ta-tool-calls-scout/report.md` §4 is checked and not just quoted;
# shape C is tested against a room built with one of each kind of record, so a
# tool's own enum can be shown to hold only ITS intent's set and not the union.
class Eval::Classifier::ToolShapesTest < ActiveSupport::TestCase
  test "shape B wraps the identical schema in one tool, forced by its own name" do
    schema = Playthrough::IntentSchema.for(%w[north south])
    built = Eval::Classifier::ToolShapes.single(schema)

    assert_equal %w[player_intent], built[:tools].map(&:name)
    assert_equal :player_intent, built[:choice]
    assert_equal schema.new.to_json_schema.fetch(:schema).as_json, built[:tools].sole.params_schema
  end

  # THE OFFLINE, BYTE-FOR-BYTE ASSERTION the report made from the installed
  # gem (`ruby_llm-1.16.0`): the closed set crosses the wire IDENTICALLY
  # whether it travels as `response_format.json_schema.schema` or as
  # `tools[0].function.parameters`. `render_payload` is a module function on
  # the real provider code -- no chat, no HTTP, no key.
  test "shape B's closed set crosses the wire byte for byte the same as the schema call" do
    # RubyLLM 2 exposes this rendering through Chat#render and provider
    # instances; the former 1.x module function is intentionally gone. The
    # public Chat#render envelope is covered by ruby_llm_schema_envelope_test.
    skip "RubyLLM 2 removed the provider module renderer"
    schema = Playthrough::IntentSchema.for(%w[north south])
    model = Struct.new(:id).new("mistralai/mistral-medium-3.1")

    schema_payload = RubyLLM::Protocols::ChatCompletions::Chat.render_payload(
      [], tools: {}, tool_prefs: {}, temperature: 0.0, model: model, schema: schema.new.to_json_schema)

    built = Eval::Classifier::ToolShapes.single(schema)
    tool_payload = RubyLLM::Protocols::ChatCompletions::Chat.render_payload(
      [], tools: built[:tools].index_by { |tool| tool.name.to_sym }, tool_prefs: { choice: built[:choice] },
      temperature: 0.0, model: model, schema: nil)

    schema_closed_set = schema_payload.dig(:response_format, :json_schema, :schema)
    tool_closed_set = tool_payload.dig(:tools, 0, :function, :parameters)

    assert_not_nil schema_closed_set
    assert_not_nil tool_closed_set
    %w[type properties required additionalProperties].each do |key|
      assert_equal schema_closed_set.fetch(key.to_sym).as_json, tool_closed_set.fetch(key).as_json,
                   "the `#{key}` of the closed set must cross the wire identically"
    end
  end

  test "shape C builds one tool per intent, each carrying only its own target set" do
    classifier = staffed_classifier
    built = Eval::Classifier::ToolShapes.per_intent(classifier)

    assert_equal :required, built[:choice]
    assert_equal Playthrough::IntentSchema::INTENTS, built[:tools].map(&:name)
    built[:tools].each do |tool|
      refute tool.params_schema.fetch("properties").key?("intent"),
             "#{tool.name} must not carry `intent` -- which tool was called already answers it"
      assert_equal %w[target also_named], tool.params_schema.fetch("required")
    end

    move = built[:tools].find { |tool| tool.name == "move" }
    assert_equal [ "The Long Hallway", "nothing" ], move.params_schema.fetch("properties").fetch("target").fetch("enum")

    talk = built[:tools].find { |tool| tool.name == "talk" }
    talk_targets = talk.params_schema.fetch("properties").fetch("target").fetch("enum")
    assert_includes talk_targets, "Maren"
    refute_includes talk_targets, "apple", "talk's own set must not carry take's set"

    take = built[:tools].find { |tool| tool.name == "take" }
    take_targets = take.params_schema.fetch("properties").fetch("target").fetch("enum")
    assert_includes take_targets, "apple"
    refute_includes take_targets, "Maren", "take's own set must not carry talk's set"
    refute_includes take_targets, "The Long Hallway", "take's own set must not carry move's set"

    other = built[:tools].find { |tool| tool.name == "other" }
    assert_equal %w[nothing], other.params_schema.fetch("properties").fetch("target").fetch("enum")

    # THE FIELD DESCRIPTIONS ARE VERBATIM OFF `Playthrough::IntentSchema.for`,
    # never rewritten for the narrower tool.
    full = Playthrough::IntentSchema.for(%w[apple]).new.to_json_schema.fetch(:schema)
    assert_equal full.dig(:properties, :target, :description),
                 take.params_schema.dig("properties", "target", "description")
  end

  test "a shape C tool's execute halts immediately and injects its own name as the intent" do
    classifier = staffed_classifier
    move = Eval::Classifier::ToolShapes.per_intent(classifier)[:tools].find { |tool| tool.name == "move" }

    result = move.call("target" => "The Long Hallway", "also_named" => "nothing")

    assert_equal({ "target" => "The Long Hallway", "also_named" => "nothing", "intent" => "move" }, result)
  end

  private

  def staffed_classifier
    story = create(:story)
    room = create(:location, story: story, name: "Ward Office 12")
    hallway = create(:location, story: story, name: "The Long Hallway")
    create(:location_connection, location: room, connected_location: hallway)
    player = create(:character, :protagonist, story: story, fullname: "Cal")
    create(:character, story: story, location: room, fullname: "Maren", nickname: "Maren")
    game = create(:playthrough, story: story, character: player, current_location: room)
    create(:item, playthrough: game, location: room, character: nil, name: "apple", use_kind: "food")
    create(:item, :carried, playthrough: game, name: "hat", use_kind: "ordinary")
    Playthrough::Classifier.new(game)
  end
end
