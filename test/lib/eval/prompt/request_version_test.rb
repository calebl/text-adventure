require "test_helper"

class Eval::Prompt::RequestVersionTest < ActiveSupport::TestCase
  test "schema-only edits move the request identity and neither legacy digest" do
    before = Eval::Prompt::RequestVersion.offline
    assert_equal before, Eval::Prompt::RequestVersion.offline
    schema = Scene::Schema.new.to_json_schema.deep_stringify_keys
    schema.fetch("schema")["description"] = "Changed schema descriptor."
    Scene::Schema.stub(:new, Struct.new(:to_json_schema).new(schema)) do
      after = Eval::Prompt::RequestVersion.offline
      refute_equal before[:request_identity], after[:request_identity]
      assert_equal before.except(:request_identity), after.except(:request_identity)
    end
  end

  test "ending scaffold renders offline with a fixed prelude and does not leak capture" do
    corpus = Eval::Prompt.corpus("ending")
    assert_equal Eval::Prompt::RequestVersion.offline(corpus), Eval::Prompt::RequestVersion.offline(corpus)
    assert_nil Thread.current[Eval::Prompt::RequestVersion::KEY]
  end
end
