require "test_helper"

# THE ONE EXTRA CALL A GENERATED WORLD MAKES, driven with the model stubbed.
#
# WHAT IT MUST NOT DO is most of what these assert: it may not create a
# `Location`, a `Character` or an `Item`, it may not bind anything, and it may
# not leave a world in a state the doctor could not describe. The arc states
# what the world must contain; the registries decide when it does.
class Quest::GeneratorTest < ActiveSupport::TestCase
  ANSWER = {
    "title" => "The Missing Warrant",
    "premise" => "Find the warrant that chained him to the post, before the water turns.",
    "steps" => [
      { "summary" => "Find the clerk who filed it.", "trigger" => "speak_to",
        "target" => "Sub-Inspector Rowe", "teaser" => "Somebody kept the copy." },
      { "summary" => "Get it into your own hands.", "trigger" => "hold_item",
        "target" => "the sealed warrant", "teaser" => "Wax, and a seal nobody wants read aloud." },
      { "summary" => "Take it where it can be answered.", "trigger" => "reach_location",
        "target" => "The Inspectorate", "teaser" => "A door at the top of the steps." }
    ],
    "outcomes" => [
      { "name" => "The Tide", "summary" => "The tide came in first.", "is_default" => false },
      { "name" => "answered", "summary" => "The warrant was read aloud.", "is_default" => true }
    ]
  }.freeze

  def setup
    @story = create(:story)
    @opening = create(:location, :stub, story: @story, name: "The Causeway Court")
  end

  def generate(answer = ANSWER)
    agent = FakeAgent.new(answer)
    quest = BaseAgent.stub(:new, agent) { Quest::Generator.new(@story).generate! }
    [ quest, agent ]
  end

  # --- what it writes --------------------------------------------------------

  test "writes the arc, its beats in order and its endings" do
    quest, = generate

    assert_equal "The Missing Warrant", quest.title
    assert_predicate quest, :main?
    assert_predicate quest, :generated?
    assert_equal [ 1, 2, 3 ], quest.steps.map(&:position)
    assert_equal %w[speak_to hold_item reach_location], quest.steps.map(&:trigger_kind)
    assert_equal "Sub-Inspector Rowe", quest.steps.first.target_name
    assert_equal "Somebody kept the copy.", quest.steps.first.teaser
  end

  test "exactly one ending is the one the world was born with, whatever order they came in" do
    quest, = generate

    assert_equal 2, quest.outcomes.count
    assert_equal 1, quest.outcomes.count(&:is_default?)
    assert_equal "The warrant was read aloud.", @story.reload.conclusion
  end

  test "an answer that marks no default still leaves exactly one" do
    answer = ANSWER.merge("outcomes" => ANSWER["outcomes"].map { |row| row.merge("is_default" => false) })
    quest, = generate(answer)

    assert_equal 1, quest.outcomes.count(&:is_default?)
    assert_equal "the-tide", quest.default_outcome.name, "the first ending is the one the world was built toward"
  end

  test "an answer that marks two defaults still leaves exactly one" do
    answer = ANSWER.merge("outcomes" => ANSWER["outcomes"].map { |row| row.merge("is_default" => true) })
    quest, = generate(answer)

    assert_equal 1, quest.outcomes.count(&:is_default?)
  end

  test "labels are made into keys a seed file can re-assert an ending under" do
    quest, = generate

    assert_includes quest.outcomes.map(&:name), "the-tide"
  end

  # --- what it must not do ---------------------------------------------------

  test "creates no place, no person and no thing" do
    assert_no_difference [ "Location.count", "Character.count", "Item.count" ] do
      generate
    end
  end

  test "binds nothing, so a brand-new world's arc is entirely unbound" do
    quest, = generate

    assert_equal quest.steps.to_a, quest.unbound_steps
    assert quest.steps.all? { |step| step.bound_at.nil? }
  end

  test "the world it leaves is one the doctor can describe and still open" do
    generate

    doctor = Story::Doctor.new(@story.reload)
    codes = doctor.findings.map(&:code)

    assert_includes codes, :quest_step_unbound
    assert_not_includes codes, :story_cannot_progress,
                        "a young generated world is supposed to be unbound"
    assert_not_includes codes, :story_without_a_conclusion
  end

  # --- what it is told -------------------------------------------------------

  test "is told the world has one room and nothing else" do
    _quest, agent = generate

    assert_includes agent.prompts.last, "The Causeway Court"
    assert_includes agent.prompts.last, "no other place, nobody else, and not one object"
    assert_includes agent.prompts.last, @story.preface
  end

  test "never asks for a number of minutes, because a model writes no free number" do
    _quest, agent = generate

    assert_not_includes Quest::Schema::TRIGGERS, "time_passed"
    assert_not_includes agent.prompts.last, "minutes"
  end

  # --- what it does when it cannot ------------------------------------------

  test "a failed call leaves no arc and raises nothing" do
    agent = Object.new
    def agent.with_instructions(_) = self
    def agent.with_schema(_) = self
    def agent.ask(_) = raise(BaseAgent::NoModelConfiguredError, "no model")

    quest = BaseAgent.stub(:new, agent) { Quest::Generator.new(@story).generate! }

    assert_nil quest
    assert_nil @story.reload.main_quest
  end

  test "an answer with no usable beat writes nothing at all, rather than an arc nobody can start" do
    answer = ANSWER.merge("steps" => [ { "summary" => "", "trigger" => "reach_location", "target" => "" } ])

    assert_no_difference [ "Quest.count", "Quest::Outcome.count" ] do
      assert_nil generate(answer).first
    end
  end

  test "an unusable beat is dropped and the rest of the arc still lands" do
    answer = ANSWER.merge("steps" => ANSWER["steps"] + [ { "summary" => "Wait.", "trigger" => "time_passed" } ])
    quest, = generate(answer)

    assert_equal 3, quest.steps.count
    assert_equal [ 1, 2, 3 ], quest.steps.map(&:position)
  end

  test "an answer with no title falls back to the story's own, because the title is a key" do
    quest, = generate(ANSWER.merge("title" => ""))

    assert_equal @story.title, quest.title
  end
end
