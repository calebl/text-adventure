require "test_helper"

# ONE MODEL, NAMED EXPLICITLY, WITH NOTHING BEHIND IT.
#
# The captain's instruction of 2026-09-04 asked for an arm selector that names
# exactly which models a run measures "instead of inheriting the rotation" and
# that does not change the app's default rotation or the `TA_LOCAL_MODELS`
# default. Both halves are tested here, and the second matters more: an
# instrument that quietly reconfigured the app would make every later
# measurement a measurement of something else.
class Eval::Classifier::ArmTest < ActiveSupport::TestCase
  test "a bare id is OpenRouter, which is what every remote id in this app looks like" do
    arm = Eval::Classifier::Arm.parse("mistralai/mistral-medium-3.1")

    assert_equal :openrouter, arm.provider
    assert_equal "mistralai/mistral-medium-3.1", arm.model
    assert_equal "mistralai/mistral-medium-3.1", arm.id
    assert_not_predicate arm, :local?
  end

  # AN OLLAMA TAG HAS A COLON IN IT, which is the whole reason the provider is a
  # prefix and the reason only ONE colon is consumed.
  test "a local spec names its provider first and keeps the tag intact" do
    arm = Eval::Classifier::Arm.parse("ollama:qwen3:8b")

    assert_equal :ollama, arm.provider
    assert_equal "qwen3:8b", arm.model
    assert_predicate arm, :local?
    assert_equal "ollama:qwen3:8b", arm.id, "a local arm keeps its provider in the label, or two rows collapse"
  end

  test "the model options are the ones BaseAgent understands, assume_model_exists and all" do
    assert_equal({ provider: :ollama, model: "gemma3:12b", assume_model_exists: true },
                 Eval::Classifier::Arm.parse("ollama:gemma3:12b").model_options)
    assert_equal({ provider: :openrouter, model: "minimax/minimax-m3", assume_model_exists: true },
                 Eval::Classifier::Arm.parse("minimax/minimax-m3").model_options)
  end

  test "a provider nobody has heard of is refused rather than read as a model name" do
    assert_raises(Eval::Classifier::Arm::UnknownProvider) do
      Eval::Classifier::Arm.new(provider: :vertex, model: "gemini")
    end
    assert_raises(Eval::Classifier::Arm::UnknownProvider) do
      Eval::Classifier::Arm.new(provider: :ollama, model: "  ")
    end
  end

  # THE POINT OF THE WHOLE CLASS. `BaseAgent` is the one gate every model call
  # goes through, so replacing its rotation for the length of a pass is the
  # whole of "measure exactly this model".
  test "pinning replaces the rotation with one model and puts it back afterwards" do
    was = BaseAgent.default_model_options

    Eval::Classifier::Arm.parse("ollama:qwen3:4b").pinned do
      assert_equal [ { provider: :ollama, model: "qwen3:4b", assume_model_exists: true } ],
                   BaseAgent.default_model_options
    end

    assert_equal was, BaseAgent.default_model_options, "the app's own rotation has to come back"
  end

  test "it puts the rotation back even when the pass raises" do
    was = BaseAgent.default_model_options

    assert_raises(RuntimeError) do
      Eval::Classifier::Arm.parse("minimax/minimax-m3").pinned { raise "the pass blew up" }
    end

    assert_equal was, BaseAgent.default_model_options,
                 "a failed pass must not leave a poisoned BaseAgent for the rest of the process"
  end

  # THE ROTATION IS OFF BY CONSTRUCTION, and this is where that claim is checked
  # against `BaseAgent#ask`'s own condition rather than asserted in a comment:
  # it retries only while `attempts < @model_options.count`, so one option never
  # retries. That is what makes a latency clean and a failure attributable.
  test "an arm of one cannot retry, which is what makes a failed call attributable" do
    Eval::Classifier::Arm.parse("ollama:qwen3:4b").pinned do
      assert_equal 1, BaseAgent.default_model_options.size,
                   "BaseAgent#ask retries only while attempts < model_options.count"
    end
  end

  test "the app's defaults are not changed, which is the other half of the instruction" do
    assert_equal %w[mistralai/mistral-medium-3.1 minimax/minimax-m3], BaseAgent::REMOTE_MODEL_IDS,
                 "the bench must not reorder or extend what a player gets"
    assert_nil ENV["TA_LOCAL_MODELS"],
               "a local arm replaces the rotation rather than joining it, so the gate stays shut"
    assert_empty BaseAgent.local_model_options,
                 "and the app's local half stays empty unless somebody asks for it"
  end

  test "a local arm is free and a hosted one is priced off the registry" do
    local = Eval::Classifier::Arm.parse("ollama:qwen3:8b")

    assert_predicate local, :free?
    assert_in_delta 0.0, local.price.of(1_000_000, 1_000_000)
    assert_not_predicate Eval::Classifier::Arm.parse("mistralai/mistral-medium-3.1"), :free?
  end

  test "arms of the same provider and model are the same arm" do
    assert_equal Eval::Classifier::Arm.parse("ollama:qwen3:8b"), Eval::Classifier::Arm.parse("ollama:qwen3:8b")
    assert_not_equal Eval::Classifier::Arm.parse("ollama:qwen3:8b"), Eval::Classifier::Arm.parse("qwen3:8b")
  end

  # THE SUFFIX COMES OFF BEFORE THE PREFIX GOES ON, which is the one ordering
  # bug available here: read the other way round, the model would be
  # `qwen3:4b+nothink` and ollama would be asked for a tag it does not have.
  test "the thinking suffix is read off the end and leaves the ollama tag intact" do
    arm = Eval::Classifier::Arm.parse("ollama:qwen3:4b+nothink")

    assert_equal :ollama, arm.provider
    assert_equal "qwen3:4b", arm.model
    assert_equal({ provider: :ollama, model: "qwen3:4b", assume_model_exists: true }, arm.model_options,
                 "the suffix is an arm's request shape and never part of the model's name")
    assert_predicate arm, :thinking_off?
    assert_equal "ollama:qwen3:4b+nothink", arm.id
  end

  # THE OTHER HALF OF `#pinned`, and the reason it is tested here as well as in
  # `BaseAgent::ProviderParamsTest`: the arm sets BOTH seams, so a pass that
  # asked for no thinking and got the app's empty default would have measured a
  # thinking model at 100 seconds a call and said otherwise.
  test "pinning sets the provider params too, and restores the app's empty default" do
    Eval::Classifier::Arm.parse("ollama:qwen3:4b+nothink").pinned do
      assert_equal({ reasoning_effort: "none" }, BaseAgent.default_provider_params)
    end

    assert_empty BaseAgent.default_provider_params

    Eval::Classifier::Arm.parse("ollama:qwen3:4b").pinned do
      assert_empty BaseAgent.default_provider_params,
                   "an arm that did not ask must not inherit the last arm's request shape"
    end
  end

  test "a list may hold specs or arms, so a caller need not know which it is holding" do
    mixed = Eval::Classifier::Arm.all([ "ollama:qwen3:4b", Eval::Classifier::Arm.parse("minimax/minimax-m3") ])

    assert_equal %w[ollama:qwen3:4b minimax/minimax-m3], mixed.map(&:id)
  end
end
