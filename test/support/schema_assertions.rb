# Helpers for asserting what a RubyLLM::Schema subclass actually produces.
#
# `to_json_schema` has had two shapes across gem versions: a provider envelope
# (`{ name:, schema: { ... } }`, which is what RubyLLM::Chat#with_schema reaches
# into) and a bare Draft 2020-12 document. The field-level contract -- names,
# types, constraints, and the required list -- is the same either way and is
# what the application actually depends on, so these helpers normalise the
# envelope away. The envelope itself is asserted separately and deliberately,
# in RubyLLMSchemaEnvelopeTest.
module SchemaAssertions
  # The JSON Schema body, with either envelope peeled off and string keys.
  def json_schema_body(schema_class)
    document = schema_class.new.to_json_schema.deep_stringify_keys
    document.key?("schema") ? document.fetch("schema") : document
  end

  def schema_properties(schema_class)
    json_schema_body(schema_class).fetch("properties")
  end

  def schema_required(schema_class)
    json_schema_body(schema_class).fetch("required")
  end

  # Asserts the field exists with the given type, and that every constraint
  # passed is present and equal. Constraints use JSON Schema spelling
  # (maxLength, minimum, enum, ...).
  def assert_schema_field(schema_class, name, type:, **constraints)
    property = schema_properties(schema_class)[name.to_s]

    assert_not_nil property, "expected #{schema_class} to define a #{name} field"
    assert_equal type.to_s, property["type"], "#{name} should be a #{type}"

    constraints.each do |key, value|
      assert_equal value, property[key.to_s], "#{name}.#{key}"
    end

    property
  end

  # Every field the app reads must be described, or the model has no idea what
  # to put in it. A blank description is the same bug as a missing one.
  def assert_every_field_described(schema_class)
    schema_properties(schema_class).each do |name, property|
      assert property["description"].present?, "#{schema_class}##{name} needs a description"
    end
  end
end
