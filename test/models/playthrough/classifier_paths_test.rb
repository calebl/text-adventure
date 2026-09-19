require "test_helper"

# WHICH READER ANSWERED, AND WHAT HAPPENS WHEN THE FIRST ONE CANNOT.
#
# `Playthrough::Classifier` has two model readers now and no feature flag: the
# presence of `TYPESAFE_API_KEY` is the whole of the switch. So the two things
# this file exists to hold still are the two that would be silent if they broke.
#
#   * WITH NO KEY THE CLASS IS WHAT IT ALWAYS WAS. Same instructions, same closed
#     enum, same prompt, same resolution, one call -- and nothing of the cascade
#     is even built. That is what every test run, every keyless checkout and
#     every machine whose key has gone missing exercises.
#   * A FAILING PROVIDER NEVER COSTS A TURN. Six ways for the cascade to fail,
#     one outcome for all six: the model call that would have been made anyway,
#     the turn plays, and the column says which.
class Playthrough::ClassifierPathsTest < ActiveSupport::TestCase
  include SchemaAssertions

  CLEAR = { "named_more_than_one" => 0.02, "target_present" => 0.95 }.freeze

  def setup
    @story = create(:story)
    @protagonist = create(:character, story: @story, fullname: "Iri Calder", is_protagonist: true)
    @here = create(:location, story: @story, name: "Ashgate Market")
    @playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
    @stamp = lying_here(@playthrough, @here, name: "ward stamp")
    @press = lying_here(@playthrough, @here, name: "filing press")
  end

  def with_key(value = "a-test-key")
    was = ENV["TYPESAFE_API_KEY"]
    ENV["TYPESAFE_API_KEY"] = value
    yield
  ensure
    ENV["TYPESAFE_API_KEY"] = was
  end

  # Drives the real classifier with a fixture at each provider boundary.
  # `typed` nil means no cascade fixture is offered at all.
  def classify(model_answer, typed: nil, command: "pick up the ward stamp")
    agent = FakeAgent.new(model_answer)
    classifier = Playthrough::Classifier.new(@playthrough, system_one: typed)
    intent = BaseAgent.stub(:new, agent) { classifier.classify(command) }

    [ intent, classifier, agent ]
  end

  def typed_agent(answers) = FakeSystemOne.new(CLEAR.merge(answers))

  # --- the keyless path, which is the path ----------------------------------

  test "with no key the classifier makes the one call it always made" do
    intent, classifier, agent = classify({ "intent" => "take", "target" => "ward stamp", "also_named" => "nothing" })

    assert_equal @stamp, intent.item
    assert_equal "model", classifier.resolved_by
    assert_equal 1, agent.prompts.size
    assert_equal Playthrough::Classifier::INSTRUCTIONS, agent.instructions
    assert_equal Playthrough::Classifier::TEMPERATURE, agent.temperature
    assert_includes agent.prompts.first, "pick up the ward stamp"
    assert_includes agent.prompts.first, "ward stamp"
  end

  test "with no key nothing of the cascade is built at all" do
    SystemOneAgent.stub(:new, ->(**) { flunk "a keyless environment built a System One agent" }) do
      _, classifier = classify({ "intent" => "take", "target" => "ward stamp", "also_named" => "nothing" })

      assert_equal "model", classifier.resolved_by
    end
  end

  test "the closed enum the keyless call is given is the whole position and nothing more" do
    _, _, agent = classify({ "intent" => "take", "target" => "ward stamp", "also_named" => "nothing" })

    assert_equal [ "ward stamp", "filing press", Playthrough::IntentSchema::NOTHING ],
                 schema_properties(agent.schemas.last).dig("target", "enum")
  end

  # --- the four values the column can hold ----------------------------------

  test "a composed line records the typed reader and makes no model call" do
    intent, classifier, agent = with_key do
      classify({ "intent" => "other", "target" => "nothing", "also_named" => "nothing" },
               typed: typed_agent("intent" => "take", "target_take" => "available_item_1"))
    end

    assert_equal @stamp, intent.item
    assert_equal "typed_model", classifier.resolved_by
    assert_empty agent.prompts, "a composed line paid for the model call as well"
  end

  test "an escalated line records the escalation and the model call answers it" do
    intent, classifier, agent = with_key do
      classify({ "intent" => "take", "target" => "filing press", "also_named" => "ward stamp" },
               typed: typed_agent("intent" => "take", "target_take" => "available_item_1",
                                  "named_more_than_one" => 0.91))
    end

    assert_equal @press, intent.item, "the model call's answer is what the turn acts on"
    assert_equal @stamp, intent.also_named
    assert_equal "typed_model_escalated", classifier.resolved_by
    assert_equal 1, agent.prompts.size
  end

  test "a failed cascade records the fall-through and the model call answers it" do
    intent, classifier, agent = with_key do
      classify({ "intent" => "take", "target" => "ward stamp", "also_named" => "nothing" },
               typed: FakeSystemOne.new(SystemOneAgent::Unavailable.new("timed out")))
    end

    assert_equal @stamp, intent.item
    assert_equal "typed_model_unavailable", classifier.resolved_by
    assert_equal 1, agent.prompts.size
  end

  test "every value this class writes is one the column accepts" do
    assert_equal Playthrough::Classifier::PATHS,
                 Playthrough::Classifier::PATHS & Playthrough::Grammar::PATHS
    assert_equal Playthrough::Classifier::MODEL_PATHS,
                 Playthrough::Classifier::MODEL_PATHS & Playthrough::Classifier::PATHS
    assert_not_includes Playthrough::Classifier::MODEL_PATHS, "typed_model"
  end

  # --- the failure policy, one test per mode --------------------------------

  # None of these is an engine refusal. A refusal is a reading of the player's
  # line; these are facts about the network, and the turn plays through all of
  # them.
  FALLING_THROUGH = {
    "a timeout" => SystemOneAgent::Unavailable.new("Net::ReadTimeout"),
    "an HTTP error" => SystemOneAgent::Unavailable.new("the provider answered 503 Service Unavailable"),
    "a malformed body" => { "nonsense" => true },
    "a mismatched answer set" => { "answers" => { "intent" => { "type" => "choice", "choice" => "take" } } },
    "an out-of-list choice" => { "intent" => "take", "target_take" => "way_9",
                                 "named_more_than_one" => 0.02, "target_present" => 0.9 }
  }.freeze

  FALLING_THROUGH.each do |what, reply|
    test "#{what} falls through to the model call and never blocks the turn" do
      intent, classifier, agent = with_key do
        classify({ "intent" => "take", "target" => "ward stamp", "also_named" => "nothing" },
                 typed: FakeSystemOne.new(reply))
      end

      assert_equal @stamp, intent.item
      assert_not_predicate intent, :refused?
      assert_equal "typed_model_unavailable", classifier.resolved_by
      assert_equal 1, agent.prompts.size
    end
  end

  # THE SIXTH MODE, and the only one that is not an error at all: a key that was
  # never there. Nothing is tried, so nothing falls through.
  test "a missing key is not a failure and records the plain model path" do
    _, classifier = classify({ "intent" => "take", "target" => "ward stamp", "also_named" => "nothing" })

    assert_equal "model", classifier.resolved_by
  end

  test "a key that goes missing between the switch and the call still plays the turn" do
    classifier = Playthrough::Classifier.new(@playthrough)
    agent = FakeAgent.new({ "intent" => "take", "target" => "ward stamp", "also_named" => "nothing" })

    intent = with_key do
      BaseAgent.stub(:new, agent) do
        # The real provider, asked with the key deleted underneath it -- which is
        # what a rotated key looks like from in here.
        ENV.delete("TYPESAFE_API_KEY")
        classifier.classify("pick up the ward stamp")
      end
    end

    assert_equal @stamp, intent.item
    assert_not_predicate intent, :refused?
  end

  # --- the reader a measurement pins ----------------------------------------

  # `Eval::Classifier` measures THIS CLASS, so it pins which reader answers the
  # way it already pins which model does. Without it a maintainer with a key in
  # their shell would score one reader's answers under another's name.
  test "a caller can pin the cascade off whatever the environment says" do
    _, classifier, agent = with_key do
      classify({ "intent" => "take", "target" => "ward stamp", "also_named" => "nothing" },
               typed: false)
    end

    assert_equal "model", classifier.resolved_by
    assert_equal 1, agent.prompts.size
  end

  # --- the measurements are taken off whichever reader answered -------------

  test "a composed reach that found nothing still writes a drift row" do
    assert_difference -> { Playthrough::Drift.count }, 1 do
      with_key do
        classify({ "intent" => "other", "target" => "nothing", "also_named" => "nothing" },
                 typed: typed_agent("intent" => "take", "target_take" => "nothing"),
                 command: "pick up the anvil")
      end
    end
  end

  test "a composed line naming two records still writes an overreach row" do
    assert_difference -> { Playthrough::Overreach.count }, 1 do
      with_key do
        classify({ "intent" => "other", "target" => "nothing", "also_named" => "nothing" },
                 typed: typed_agent("intent" => "take", "target_take" => "available_item_1",
                                    "also_named" => "available_item_2"),
                 command: "take the stamp and the press")
      end
    end
  end
end
