require "test_helper"
require "active_support/testing/constant_stubbing"

class Eval::Classifier::VersionTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::ConstantStubbing
  test "identity is deterministic and notices instructions and closed labels" do
    before = Eval::Classifier::Version.offline
    assert_equal before, Eval::Classifier::Version.offline
    details = Eval::Classifier::Version.offline_details
    assert_equal before, details[:request_identity]
    assert_predicate details[:prompt_digest], :present?
    assert_predicate details[:instructions_digest], :present?
    stub_const(Playthrough::Classifier, :INSTRUCTIONS, Playthrough::Classifier::INSTRUCTIONS + " Changed.") do
      refute_equal before, Eval::Classifier::Version.offline
    end
    original = Playthrough::IntentSchema.method(:for)
    Playthrough::IntentSchema.stub(:for, ->(names) { original.call(names + [ "a changed closed label" ]) }) do
      refute_equal before, Eval::Classifier::Version.offline
    end
  end
end
