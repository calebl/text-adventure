require "test_helper"

# WHICH READER ANSWERED, AND WHAT HAPPENS WHEN THE FIRST ONE CANNOT.
#
# A line is read by System One first where either credential is present, and
# by the classifier model where System One is off, escalates or fails. That
# reading is the engine's (`renderedstep_engine::classifier`), and it is what
# the classifier bench measures: `Playthrough::Requests.read_line`, each call
# answered through the bench's own `Eval::Classifier::Bench::Answering`. So the
# two things this file exists to hold still are the two that would be silent if
# they broke:
#
#   * WITH NO KEY THE READING IS ONE MODEL CALL. The Ruby reference loop the
#     suite plays reads that way always (`Playthrough::Classifier`), and so
#     does the engine where System One is off.
#   * A FAILING PROVIDER NEVER COSTS A TURN. Every way for the cascade to fail
#     ends the same way: the model call that would have been made anyway, and
#     the reader recorded says which.
class Playthrough::ClassifierPathsTest < ActiveSupport::TestCase
  include SchemaAssertions

  CLEAR = { "named_more_than_one" => 0.02, "target_present" => 0.95 }.freeze
  TAKE_THE_STAMP = { "intent" => "take", "target" => "ward stamp", "also_named" => "nothing" }.freeze

  def setup
    @story = create(:story)
    @protagonist = create(:character, story: @story, fullname: "Iri Calder", is_protagonist: true)
    @here = create(:location, story: @story, name: "Ashgate Market")
    @playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
    @stamp = lying_here(@playthrough, @here, name: "ward stamp")
    @press = lying_here(@playthrough, @here, name: "filing press")
  end

  # --- the Ruby reference loop: the model call alone -------------------------

  def classify(model_answer, command: "pick up the ward stamp")
    agent = FakeAgent.new(model_answer)
    classifier = Playthrough::Classifier.new(@playthrough)
    intent = BaseAgent.stub(:new, agent) { classifier.classify(command) }

    [ intent, classifier, agent ]
  end

  test "the reference loop's classifier makes the one call it always made" do
    intent, classifier, agent = classify(TAKE_THE_STAMP)

    assert_equal @stamp, intent.item
    assert_equal "model", classifier.resolved_by
    assert_equal 1, agent.prompts.size
    assert_equal Playthrough::Classifier::INSTRUCTIONS, agent.instructions
    assert_equal Playthrough::Classifier::TEMPERATURE, agent.temperature
    assert_includes agent.prompts.first, "pick up the ward stamp"
  end

  test "the reference loop asks nobody but the model, whatever the environment says" do
    with_key do
      SystemOneAgent.stub(:new, ->(**) { flunk "the reference loop built a System One agent" }) do
        _, classifier = classify(TAKE_THE_STAMP)

        assert_equal "model", classifier.resolved_by
      end
    end
  end

  test "the closed enum the model call is given is the whole position and nothing more" do
    _, _, agent = classify(TAKE_THE_STAMP)

    assert_equal [ "ward stamp", "filing press", Playthrough::IntentSchema::NOTHING ],
                 schema_properties(agent.schemas.last).dig("target", "enum")
  end

  test "every reader a line can record is one the column accepts" do
    assert_equal Playthrough::Classifier::PATHS,
                 Playthrough::Classifier::PATHS & Playthrough::Grammar::PATHS
    assert_equal Playthrough::Classifier::MODEL_PATHS,
                 Playthrough::Classifier::MODEL_PATHS & Playthrough::Classifier::PATHS
    assert_not_includes Playthrough::Classifier::MODEL_PATHS, "typed_model"
  end

  # --- the engine's reading, as the bench measures it -------------------------

  # One line read by the engine, System One answered by `typed` (a
  # `FakeSystemOne`, or nil for no cascade) and the model call by
  # `model_answer`. Answers [reading, agent, system_one].
  def read(model_answer, typed: nil, command: "pick up the ward stamp")
    agent = FakeAgent.new(model_answer)
    bench = Eval::Classifier::Bench.new(corpus: Eval::Classifier.corpus, arms: [ "fake/model" ], reps: 1, io: nil,
                                        cascade: !typed.nil?)
    arm = bench.arms.sole
    answering = Eval::Classifier::Bench::Answering.new(bench, arm, @playthrough, Playthrough::Requests.rows)
    reading = BaseAgent.stub(:new, agent) do
      SystemOneAgent.stub(:new, ->(**) { typed }) do
        SystemOneAgent.stub(:configured?, !typed.nil?) do
          Playthrough::Requests.read_line(@playthrough, command, system_one: !typed.nil?, &answering.method(:call))
        end
      end
    end

    [ reading, agent, typed ]
  end

  def typed_agent(answers) = FakeSystemOne.new(CLEAR.merge(answers))

  test "with System One off the engine reads with the one model call" do
    reading, agent = read(TAKE_THE_STAMP)

    assert_equal "ward stamp", reading.dig("intent", "target")
    assert_equal "model", reading["resolved_by"]
    assert_equal 1, agent.prompts.size
    assert_equal Playthrough::Classifier::INSTRUCTIONS, agent.instructions
  end

  test "a composed line records the typed reader and makes no model call" do
    reading, agent = read(TAKE_THE_STAMP, typed: typed_agent("intent" => "take", "target_take" => "available_item_1"))

    assert_equal "ward stamp", reading.dig("intent", "target")
    assert_equal "typed_model", reading["resolved_by"]
    assert_empty agent.prompts, "a composed line paid for the model call as well"
    assert_in_delta 0.95, reading["target_present"]
  end

  test "an escalated line records the escalation and the model call answers it" do
    reading, agent = read({ "intent" => "take", "target" => "filing press", "also_named" => "ward stamp" },
                          typed: typed_agent("intent" => "take", "target_take" => "available_item_1",
                                             "named_more_than_one" => 0.91))

    assert_equal "filing press", reading.dig("intent", "target"), "the model call's answer is what the turn acts on"
    assert_equal "ward stamp", reading.dig("intent", "also_named"),
                 "and its second name with it, so the one-line-one-act refusal is not disarmed"
    assert reading.dig("intent", "named_more_than_one")
    assert reading.dig("intent", "refused")
    assert_equal "typed_model_escalated", reading["resolved_by"]
    assert_in_delta 0.91, reading["named_more_than_one"]
    assert_equal 1, agent.prompts.size
  end

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
      reading, agent = read(TAKE_THE_STAMP, typed: FakeSystemOne.new(reply))

      assert_equal "ward stamp", reading.dig("intent", "target")
      assert_not reading.dig("intent", "refused")
      assert_equal "typed_model_unavailable", reading["resolved_by"]
      assert_equal 1, agent.prompts.size
    end
  end

  private

  def with_key(value = "a-test-key")
    was = ENV["TYPESAFE_API_KEY"]
    ENV["TYPESAFE_API_KEY"] = value
    yield
  ensure
    ENV["TYPESAFE_API_KEY"] = was
  end
end
