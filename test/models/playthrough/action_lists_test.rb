require "test_helper"

# THE CLOSED ACTION LISTS, HELD IN STEP WITH EACH OTHER. The acts a turn can be
# are named in several places -- the classifier's enum, the counters that
# validate a row against it, the request the engine sends and the scene labels
# -- and each file's header says why its list is the shape it is. Nothing here
# restates those lists; it asserts only how they relate, so a word added to one
# and forgotten in another fails here rather than as a validation error on a
# row nobody reads, or a word a model is offered that the app cannot act on.
class Playthrough::ActionListsTest < ActiveSupport::TestCase
  INTENTS = Playthrough::IntentSchema::INTENTS
  REQUEST = EngineData.fetch("playthrough/classifier/request")

  test "a reach that can miss is an intent that reaches into a closed set" do
    assert_empty Playthrough::Drift::ACTIONS - INTENTS
    assert_empty Playthrough::Drift::ACTIONS & %w[examine other]
    assert_empty Playthrough::Overreach::ACTIONS - INTENTS
    assert_empty Playthrough::Overreach::ACTIONS - REQUEST.fetch("targets").keys,
                 "every act a counter can record needs a list the request offers it"
  end

  test "the request describes every intent but the one only the grammar reads" do
    assert_empty REQUEST.fetch("intent_criteria").keys - INTENTS
    assert_equal %w[throw], INTENTS - REQUEST.fetch("intent_criteria").keys
    assert_empty REQUEST.fetch("targets").keys - INTENTS
  end

  test "the classifier bench scores the live enum" do
    assert_equal INTENTS.map(&:to_sym), Eval::Classifier::INTENTS
  end

  test "every label the engine writes or narrates is a scene action" do
    assert_empty INTENTS - Scene::ACTIONS
    assert_empty Scene::ENGINE_AUTHORED - Scene::ACTIONS
    assert_empty EngineData.fetch("scene/narrator").fetch("doing").keys - Scene::ACTIONS
  end
end
