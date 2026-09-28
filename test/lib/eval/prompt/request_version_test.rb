require "test_helper"

class Eval::Prompt::RequestVersionTest < ActiveSupport::TestCase
  test "schema-only edits move the request identity and neither legacy digest" do
    before = Eval::Prompt::RequestVersion.offline
    assert_equal before, Eval::Prompt::RequestVersion.offline
    requests = Eval::Prompt::RequestVersion.requests
    assert_equal before[:request_identity], Eval::RequestIdentity.of(requests)

    shape, schemad = requests.find { |_, request| request[:schema] }
    changed = JSON.parse(JSON.generate(schemad[:schema]))
    changed.fetch("schema")["description"] = "Changed schema descriptor."
    edited = requests.merge(shape => schemad.merge(schema: changed))

    refute_equal before[:request_identity], Eval::RequestIdentity.of(edited)
    assert_equal before[:prompt_digest], Eval::Prompt::Version.digest(edited.map { |name, request| "#{name}\n#{request[:user]}" })
  end

  test "ending scaffold renders offline, the same every time" do
    corpus = Eval::Prompt.corpus("ending")
    assert_equal Eval::Prompt::RequestVersion.offline(corpus), Eval::Prompt::RequestVersion.offline(corpus)
  end
end
