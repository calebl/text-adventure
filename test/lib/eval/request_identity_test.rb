require "test_helper"

class Eval::RequestIdentityTest < ActiveSupport::TestCase
  test "schema serialization covers descriptions enums nesting bounds and required lists" do
    schema = Location::ExitsSchema.new.to_json_schema.deep_stringify_keys
    original = Eval::RequestIdentity.of(Eval::RequestIdentity.request("system", "user", Location::ExitsSchema))
    %w[description enum properties minimum required].each do |field|
      edited = schema.deep_dup
      edited.fetch("schema")[field] = "changed only in the schema"
      instance = Struct.new(:to_json_schema).new(edited)
      Location::ExitsSchema.stub(:new, instance) do
        refute_equal original, Eval::RequestIdentity.of(Eval::RequestIdentity.request("system", "user", Location::ExitsSchema))
      end
    end
  end

  test "legacy kept sets remain readable and never acquire invented schema evidence" do
    %w[Prompt Realization Classifier].each do |kind|
      namespace = Eval.const_get(kind)
      Dir.glob(Eval.kept_root.join("*", namespace::RESULTS)).each do |file|
        document = JSON.parse(File.read(file))
        result = namespace::Result.load(File.dirname(file))
        if document["request_identity"]
          assert_equal document["request_identity"], result.request_identity
          assert_equal result.request_identity, result.summary.request_identity
        else
          assert_nil result.request_identity
          assert_nil result.summary.request_identity
        end
        if result.request_identity.nil?
          assert_equal "no schema identity recorded", Eval::RequestIdentity.label(result.request_identity)
          refute Eval::RequestIdentity.changed?(result.request_identity, Eval::RequestIdentity.of("today"))
        end
      end
    end
  end

  test "new identity survives summary disk and all comparison policies" do
    %w[Prompt Realization Classifier].each do |kind|
      namespace = Eval.const_get(kind)
      left = namespace::Result.new(corpus_size: 0, arms: [ "fake/model" ], reps: 4, passes: [],
                                   request_identity: Eval::RequestIdentity.of("before"))
      right = namespace::Result.new(corpus_size: 0, arms: [ "fake/model" ], reps: 4, passes: [],
                                    request_identity: Eval::RequestIdentity.of("after"))
      Dir.mktmpdir do |dir|
        left.summary.write!(dir)
        assert_equal left.request_identity, namespace::Result.load(dir).request_identity
      end
      output = StringIO.new
      comparison = namespace::Comparison.new(left, right, io: output)
      comparison.print
      if kind == "Classifier"
        assert_includes output.string, "DIFFERENT SCHEMA REQUEST IDENTITIES"
      else
        assert comparison.cross_prompt?
        assert_includes output.string, "PROMPT comparison"
        right.arms.replace([ "another/model" ])
        assert comparison.cross_model?
        output.truncate(0)
        comparison.print
        assert_includes output.string, "THE MODEL AND THE PROMPT BOTH CHANGED"
      end
      board = namespace::Board.new([ [ "before", left ], [ "after", right ] ])
      assert_includes board.lines.join, Eval::RequestIdentity.label(left.request_identity)
      assert_includes board.warnings.join, "different schema request identities"
    end
  end

  test "manifest freezes request measurement code" do
    %w[lib/eval/request_identity.rb lib/eval/prompt/request_version.rb
       lib/eval/realization/request_version.rb lib/eval/classifier/version.rb].each do |file|
      assert_includes Eval::MEASUREMENT_FILES, file
    end
  end
end
