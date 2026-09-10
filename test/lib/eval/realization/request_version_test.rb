require "test_helper"

class Eval::Realization::RequestVersionTest < ActiveSupport::TestCase
  test "schema-only descriptor edit moves the request identity and leaves legacy identities unchanged" do
    before = Eval::Realization::RequestVersion.offline
    legacy = Eval::Realization::Version.offline
    assert_equal before, Eval::Realization::RequestVersion.offline
    schema = Location::ExitsSchema.new.to_json_schema.deep_stringify_keys
    inside = schema.fetch("schema").fetch("properties").fetch("exits").fetch("items").fetch("properties").fetch("inside")
    inside["description"] = inside.fetch("description").sub("almost", "nearly")
    Location::ExitsSchema.stub(:new, Struct.new(:to_json_schema).new(schema)) do
      refute_equal before, Eval::Realization::RequestVersion.offline
      assert_equal legacy, Eval::Realization::Version.offline
    end
  end

  test "normalizing rolled inputs preserves literal people and slot directions" do
    kase = Eval::Realization.corpus.cases.find { |candidate| candidate.shape.to_s != "place" }
    Eval::Realization::Stage.open([ kase ]) do |stages|
      generator = stages.fetch(kase.id).generator
      before = Eval::RequestIdentity.of(Eval::Realization::RequestVersion.built(generator, 2))
      original = generator.method(:people_instructions)
      generator.stub(:people_instructions, -> { original.call.sub("EXACTLY", "ONLY") }) do
        refute_equal before, Eval::RequestIdentity.of(Eval::Realization::RequestVersion.built(generator, 2))
      end
      slots = generator.method(:slot_details)
      generator.stub(:slot_details, ->(wanted) { slots.call(wanted).sub("about", "aged") }) do
        refute_equal before, Eval::RequestIdentity.of(Eval::Realization::RequestVersion.built(generator, 2))
      end
    end
  end
end
