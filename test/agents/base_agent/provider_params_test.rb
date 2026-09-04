require "test_helper"

# THE SEAM THAT IS EMPTY, AND THE TEST THAT KEEPS IT EMPTY.
#
# `BaseAgent.default_provider_params` exists so a classifier bench arm can ask
# ollama for `think: false` -- qwen3:4b answers a classifier prompt in 2.95
# seconds without thinking and does not answer inside 120 with it, so a bench
# arm that cannot say so is not measuring the classifier, it is measuring a
# reasoning trace. The captain approved the seam on 2026-09-04 with a condition:
# **no change to BaseAgent's shipped behaviour, and a test pinning that the
# default request carries no such parameter.** This is that test.
#
# THE FAILURE IT GUARDS is a default that quietly grows a parameter, because
# this one method sits in front of EVERY model call in the app -- the narrator,
# the arrival, every character, the classifier on every turn. Something added
# here would change all of them at once, silently, on providers that need not
# accept it.
class BaseAgent::ProviderParamsTest < ActiveSupport::TestCase
  # A model that needs no key and no registry row, so these tests reach
  # `#build_chat` without an OpenRouter key in the environment.
  OPTIONS = [ { provider: :ollama, model: "a-model", assume_model_exists: true } ].freeze

  test "the shipped default is empty, so no call in the app carries a provider parameter" do
    assert_empty BaseAgent.default_provider_params,
                 "nothing in app/ may fill this in -- read the method's comment. Making the app fast on " \
                 "ollama is a change to the app, to be decided on its own evidence and not as a side effect " \
                 "of an instrument."
  end

  test "a chat built by an ordinary agent is never given provider params" do
    asked = []
    chat = watched(asked)

    BaseAgent.new(purpose: "classifier", chat: chat, model_options: OPTIONS).chat

    assert_empty asked, "the default path must not call with_params at all, not even with an empty hash"
  end

  # AND THE SEAM WORKS WHEN SOMETHING ASKS -- through the same public class
  # method the bench replaces, so this is the mechanism and not a mock of it.
  test "a replaced default reaches the chat, which is what a bench arm uses" do
    asked = []
    chat = watched(asked)

    BaseAgent.stub(:default_provider_params, { think: false }) do
      BaseAgent.new(purpose: "classifier", chat: chat, model_options: OPTIONS).chat
    end

    assert_equal [ { think: false } ], asked
  end

  # THE INSTRUMENT PUTS IT BACK. A bench pass that left this replaced would make
  # every later call in the process carry the parameter.
  test "an arm's pinning is undone even when the pass raises" do
    assert_raises(RuntimeError) do
      Eval::Classifier::Arm.parse("ollama:qwen3:4b+nothink").pinned { raise "the pass blew up" }
    end

    assert_empty BaseAgent.default_provider_params
  end

  # AND IT IS FOR A LOCAL ARM ONLY. Changing the shape of a REMOTE request is
  # not what the seam is for, and a typo asking for it should be loud.
  test "a hosted arm cannot carry provider params" do
    error = assert_raises(Eval::Classifier::Arm::UnknownProvider) do
      Eval::Classifier::Arm.new(provider: :openrouter, model: "minimax/minimax-m3",
                                provider_params: { think: false })
    end

    assert_match(/only for a local arm/, error.message)
  end

  test "asking for no thinking is explicit in the spec and in the label" do
    asked = Eval::Classifier::Arm.parse("ollama:qwen3:8b+nothink")
    plain = Eval::Classifier::Arm.parse("ollama:qwen3:8b")

    assert_predicate asked, :thinking_off?
    assert_equal({ think: false }, asked.provider_params)
    assert_equal "ollama:qwen3:8b+nothink", asked.id

    assert_not_predicate plain, :thinking_off?
    assert_empty plain.provider_params, "a run that does not ask measures the model as the app would use it"
    assert_not_equal asked, plain, "one model with thinking on and off is two measurements, not one"
  end

  private
    def watched(asked)
      Chat.new(purpose: "classifier").tap do |chat|
        chat.define_singleton_method(:with_params) do |**params|
          asked << params
          self
        end
      end
    end
end
