require "test_helper"

# The seam between our schema classes and RubyLLM.
#
# `RubyLLM::Chat#with_schema` does not hand the schema object to the provider.
# It calls `to_json_schema` and then reaches into the result for a particular
# key. Which key, and what `to_json_schema` returns, are both owned by gems we
# do not control -- and they have moved independently of each other. When they
# disagree the schema is dropped on the floor with no error at all, and the
# model answers in prose. BaseAgent#verify_schema_honored! exists because of
# that failure mode; these tests exist so it is visible before it ships.
class RubyLLMSchemaEnvelopeTest < ActiveSupport::TestCase
  include SchemaAssertions

  SCHEMAS = [ Character::BaseSchema, Character::BackgroundSchema, Interaction::Schema ].freeze

  test "every schema class is a RubyLLM::Schema" do
    SCHEMAS.each { |schema| assert_operator schema, :<, RubyLLM::Schema }
  end

  # BaseAgent#missing_schema_keys relies on this class method to decide whether
  # a response honored the schema. Without it that check silently does nothing.
  test "every schema exposes its required properties to BaseAgent" do
    SCHEMAS.each do |schema|
      assert_respond_to schema, :required_properties
      assert_equal schema_required(schema), schema.required_properties.map(&:to_s)
    end
  end

  test "every schema produces a body RubyLLM can hand to a provider" do
    SCHEMAS.each do |schema|
      body = json_schema_body(schema)

      assert_equal "object", body["type"]
      assert body["properties"].present?
      assert body["required"].present?
    end
  end

  # This is the whole ball game: what `with_schema` actually stores. It is
  # asserted end to end rather than by reading `to_json_schema`, because the
  # bug this catches lives in the gap between the two.
  test "with_schema delivers our schema to the chat" do
    # KNOWN BROKEN on the currently locked gems, and the reason this file
    # exists. ruby_llm 1.8.2 does `to_json_schema[:schema]`, expecting the
    # provider envelope. ruby_llm-schema 1.0.0 is a shim over schematist, whose
    # `to_json_schema` returns a bare Draft 2020-12 document with no `:schema`
    # key -- so the lookup yields nil and every structured call in this app is
    # currently made with no schema attached. Nothing errors; the model just
    # answers in prose. Remove this skip once the gems agree again.
    skip "ruby_llm 1.8.2 + ruby_llm-schema 1.0.0 drop the schema silently"

    SCHEMAS.each do |schema|
      chat = RubyLLM::Chat.new(provider: :ollama, model: "gemma3:12b", assume_model_exists: true)
      chat.with_schema(schema)

      delivered = chat.schema

      assert_not_nil delivered,
                     "RubyLLM::Chat#with_schema dropped #{schema}: the model will be asked for " \
                     "structured output with no schema attached and will answer in prose."
      assert_equal schema_properties(schema).keys, delivered.deep_stringify_keys["properties"].keys
    end
  end
end
