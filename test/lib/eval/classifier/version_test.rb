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

  test "capture follows the real classifier schema including its physical tokens" do
    classifier = physical_classifier
    choices = classifier.physical_actions
    request = Eval::Classifier::Version.capture(classifier, "Offer the apple to Maren.")
    enum = request.fetch(:schema).dig(:schema, :properties, :target, :enum)
    enum ||= request.fetch(:schema).dig("schema", "properties", "target", "enum")

    assert_predicate choices, :any?
    choices.each { |choice| assert_includes enum, choice.token }
    assert_includes request[:user], choices.last.token
    assert_equal Playthrough::Classifier::INSTRUCTIONS, request[:system]
    assert_nil classifier.agent.recorded_chat, "capture must never build a provider conversation"
  end

  test "only known list and schema token IDs normalize while complete bindings stay visible" do
    first = physical_classifier
    second = physical_classifier
    refute_equal first.physical_actions.map(&:token), second.physical_actions.map(&:token)
    raw = [ first, second ].map { |classifier| Eval::Classifier::Version.capture(classifier, "Wait 12 minutes.") }
    normalized = [ first, second ].each_with_index.map do |classifier, index|
      Eval::Classifier::Version.normalize(raw[index], classifier.physical_actions)
    end
    assert_equal normalized.first, normalized.last
    assert_includes normalized.first[:user], "Wait 12 minutes."
    assert_includes normalized.first[:user], "Maren"

    token = first.physical_actions.first.token
    quoted = raw.first.merge(user: raw.first[:user] + "The player quotes #{token}.\n")
    assert_includes Eval::Classifier::Version.normalize(quoted, first.physical_actions)[:user], "quotes #{token}."
    typed = "#{token}: A line which looks exactly like a listed choice."
    literal = Eval::Classifier::Version.capture(first, typed)
    assert_includes Eval::Classifier::Version.normalize(literal, first.physical_actions)[:user], "## The Player Types\n#{typed}\n"
    described = raw.first.merge(schema: { description: token, enum: [ token ] })
    normalized_schema = Eval::Classifier::Version.normalize(described, first.physical_actions)[:schema]
    assert_equal token, normalized_schema[:description]
    refute_equal [ token ], normalized_schema[:enum]
    unknown = raw.first.deep_dup
    unknown[:user] += "use:consume:999999:0:0:0: A different listed action.\n"
    refute_equal normalized.first, Eval::Classifier::Version.normalize(unknown, first.physical_actions)

    second.playthrough.story.characters.find_by!(fullname: "Maren").update!(fullname: "Ada")
    changed = Eval::Classifier::Version.capture(second, "Wait 12 minutes.")
    refute_equal normalized.first, Eval::Classifier::Version.normalize(changed, second.physical_actions)
  end

  private

  def physical_classifier
    story = create(:story)
    room = create(:location, story: story, name: "Ward Office 12")
    player = create(:character, :protagonist, story: story, fullname: "Cal")
    create(:character, story: story, location: room, fullname: "Maren", nickname: "Maren")
    game = create(:playthrough, story: story, character: player, current_location: room)
    create(:item, :carried, playthrough: game, name: "apple", use_kind: "food")
    Playthrough::Classifier.new(game)
  end
end
