require "test_helper"

# WHICH MODEL EACH JOB REACHES FIRST, pinned per caller rather than per
# constant.
#
# The point of the split is that two measurements disagree and each path takes
# the one that was measured on it: `minimax/minimax-m3` writes ~1.7x as much
# prose on the narrator path and ~3.4x on the interaction path, while
# `mistralai/mistral-medium-3.1` drops no required `Interaction::Schema` field
# where minimax dropped them on 29% of talk turns, and answers in a third of the
# time. See `data/ta-refusal-range/report.md` and the notes on both constants.
#
# ASSERTED THROUGH THE REAL CALLERS, not by re-reading the constants they are
# supposed to use. A test that only compared `PROSE_MODEL_IDS` to a literal
# would still pass on the day somebody reorders `REMOTE_MODEL_IDS` and the
# narrator quietly comes with it, which is exactly the regression this exists
# to catch. Every case below builds the object the app builds and asks the
# agent it actually holds what model it is pointed at.
class ModelSelectionTest < ActiveSupport::TestCase
  PROSE_FIRST = "minimax/minimax-m3".freeze
  SCHEMA_FIRST = "mistralai/mistral-medium-3.1".freeze

  # A key, or `default_model_options` skips the hosted models entirely and every
  # case here reads the same ollama model.
  def setup
    @previous_key = ENV["OPENROUTER_API_KEY"]
    @previous_model = ENV["OPENROUTER_MODEL"]
    ENV["OPENROUTER_API_KEY"] = "sk-test"
    ENV.delete("OPENROUTER_MODEL")
  end

  def teardown
    @previous_key.nil? ? ENV.delete("OPENROUTER_API_KEY") : ENV["OPENROUTER_API_KEY"] = @previous_key
    @previous_model.nil? ? ENV.delete("OPENROUTER_MODEL") : ENV["OPENROUTER_MODEL"] = @previous_model
  end

  test "the two orders are the same two models, opposite ways round" do
    assert_equal [ SCHEMA_FIRST, PROSE_FIRST ], BaseAgent::REMOTE_MODEL_IDS
    assert_equal [ PROSE_FIRST, SCHEMA_FIRST ], BaseAgent::PROSE_MODEL_IDS
  end

  # Mistral second on the prose list is not cosmetic: it is the model measured
  # to have written every one of the 8 charged prompts minimax refused, so it is
  # what `RefusalError`'s rotation lands on. See BaseAgent::RefusalError.
  test "the prose order keeps a known-compliant model behind the first one" do
    assert_equal SCHEMA_FIRST, BaseAgent::PROSE_MODEL_IDS.second
  end

  test "the narrator asks a model for prose first" do
    playthrough = create(:playthrough, :started)

    assert_equal PROSE_FIRST, first_model(Scene::Narrator.new(playthrough).send(:agent))
  end

  # One class, one turn, two passes, two orders. The schema'd character pass is
  # not prose and must not follow the narration pass onto the prose list.
  test "the interaction narration pass is prose and its character pass is not" do
    playthrough = create(:playthrough, :started)
    character = create(:character, story: playthrough.story)
    agent = InteractionAgent.new(character, playthrough: playthrough)

    assert_equal PROSE_FIRST, first_model(agent.narrator_agent)
    assert_equal SCHEMA_FIRST, first_model(agent.character_agent)
  end

  test "the classifier keeps the schema'd order" do
    playthrough = create(:playthrough, :started)

    assert_equal SCHEMA_FIRST,
                 first_model(Playthrough::Classifier.new(playthrough).send(:agent))
  end

  test "arrival generation keeps the schema'd order" do
    playthrough = create(:playthrough, :started)

    assert_equal SCHEMA_FIRST,
                 first_model(Scene::Generator.new(playthrough.current_location, playthrough: playthrough).send(:agent))
  end

  test "the world generators keep the schema'd order" do
    assert_equal SCHEMA_FIRST, BaseAgent.new.current_model[:model]
    assert_equal SCHEMA_FIRST, first_model(Location::Generator.new(create(:location)).send(:agent))
  end

  # An offline run is one installation of ollama, not two. The split is about
  # which hosted model answers, and there is nothing to split when none does.
  test "with no key both orders are the same local list" do
    ENV.delete("OPENROUTER_API_KEY")

    assert_equal BaseAgent::LOCAL_MODEL_OPTIONS, BaseAgent.default_model_options
    assert_equal BaseAgent::LOCAL_MODEL_OPTIONS, BaseAgent.prose_model_options
  end

  # OPERATOR PINS BEAT BOTH ORDERS. Somebody who names a model is saying "use
  # this model", and a pin that reached only the schema'd half would silently
  # leave the half a player reads on a different model than they asked for.
  test "OPENROUTER_MODEL is unshifted onto both orders" do
    ENV["OPENROUTER_MODEL"] = "vendor/override"

    assert_equal "vendor/override", BaseAgent.default_model_options.first[:model]
    assert_equal "vendor/override", BaseAgent.prose_model_options.first[:model]
    assert_equal PROSE_FIRST, BaseAgent.prose_model_options.second[:model]
  end

  # Each list keeps its own tail behind the pin, so a pinned run still falls
  # back the way that path was ordered.
  test "a pin does not flatten the two orders into one" do
    ENV["OPENROUTER_MODEL"] = "vendor/override"

    remote = ->(options) { options.select { |o| o[:provider] == :openrouter }.map { |o| o[:model] } }

    assert_equal [ "vendor/override", SCHEMA_FIRST, PROSE_FIRST ], remote.call(BaseAgent.default_model_options)
    assert_equal [ "vendor/override", PROSE_FIRST, SCHEMA_FIRST ], remote.call(BaseAgent.prose_model_options)
  end

  private

  def first_model(agent)
    agent.model_options.first[:model]
  end
end
