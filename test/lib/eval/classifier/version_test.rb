require "test_helper"
require "active_support/testing/constant_stubbing"

class Eval::Classifier::VersionTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::ConstantStubbing
  test "identity is deterministic and notices instructions and closed labels" do
    before = Eval::Classifier::Version.offline
    assert_equal before, Eval::Classifier::Version.offline
    stub_const(Playthrough::Classifier, :INSTRUCTIONS, Playthrough::Classifier::INSTRUCTIONS + " Changed.") do
      refute_equal before, Eval::Classifier::Version.offline
    end
    original = Playthrough::IntentSchema.method(:for)
    Playthrough::IntentSchema.stub(:for, ->(names) { original.call(names + [ "a changed closed label" ]) }) do
      refute_equal before, Eval::Classifier::Version.offline
    end
  end
end
