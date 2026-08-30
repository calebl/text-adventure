require "test_helper"

class Story::GeneratorTest < ActiveSupport::TestCase
  CONTENT = {
    "title" => "The Drowned Ledger",
    "genre" => "drowned-city noir",
    "preface" => "You are ankle deep in water that was not here yesterday.",
    "summary" => "A debt collector works the flooded tiers as the pumps fail."
  }.freeze

  def setup
    @universe = create(:universe)
  end

  def generate_with(agent, premise: nil)
    BaseAgent.stub(:new, agent) do
      Story::Generator.new(@universe, premise: premise).generate
    end
  end

  test "assigns every story attribute from the response" do
    story = generate_with(FakeAgent.new(CONTENT))

    assert_equal "The Drowned Ledger", story.title
    assert_equal "drowned-city noir", story.genre
    assert_equal "You are ankle deep in water that was not here yesterday.", story.preface
    assert_equal "A debt collector works the flooded tiers as the pumps fail.", story.summary
  end

  test "belongs to the universe it was generated from" do
    assert_equal @universe, generate_with(FakeAgent.new(CONTENT)).universe
  end

  test "sets a start time so the story is valid" do
    story = generate_with(FakeAgent.new(CONTENT))

    assert_not_nil story.start_time
    assert story.valid?
  end

  test "does not persist the story" do
    assert generate_with(FakeAgent.new(CONTENT)).new_record?
  end

  test "asks for the story schema" do
    agent = FakeAgent.new(CONTENT)
    generate_with(agent)

    assert_equal [ Story::Schema ], agent.schemas
  end

  test "includes the universe details in the prompt" do
    agent = FakeAgent.new(CONTENT)
    generate_with(agent)

    assert_includes agent.prompts.first, @universe.politics
    assert_includes agent.prompts.first, @universe.geographies
  end

  test "includes the premise in the prompt" do
    agent = FakeAgent.new(CONTENT)
    generate_with(agent, premise: "a heist during the flood")

    assert_includes agent.prompts.first, "a heist during the flood"
  end

  test "strips emoji from generated text" do
    agent = FakeAgent.new(CONTENT.merge("title" => "The Drowned Ledger 🌊"))

    assert_equal "The Drowned Ledger", generate_with(agent).title
  end

  test "raises when the model call fails" do
    failing = Object.new
    def failing.with_instructions(_) = self
    def failing.with_schema(_) = self
    def failing.ask(_) = raise(RubyLLM::Error.new(nil, "boom"))

    assert_raises(RubyLLM::Error) { generate_with(failing) }
  end
end
