require "test_helper"

class Story::GeneratorTest < ActiveSupport::TestCase
  CONTENT = {
    "title" => "The Drowned Ledger",
    "genre" => "drowned-city noir",
    "preface" => "You are ankle deep in water that was not here yesterday.",
    "summary" => "A debt collector works the flooded tiers as the pumps fail.",
    "opening_location_name" => "The Drowned Ledger",
    "opening_location_teaser" => "A counting house with the tide coming in."
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

  # The opening room comes back from the same call that wrote the preface, and
  # is attached as a stub so saving the story saves it too. Without this a
  # separate model call is needed just to name the room the preface describes.
  test "builds the opening location as a stub on the story" do
    story = generate_with(FakeAgent.new(CONTENT))

    assert_equal 1, story.locations.size

    opening = story.locations.first
    assert_equal "The Drowned Ledger", opening.name
    assert_equal "A counting house with the tide coming in.", opening.teaser
    assert opening.stub?
    assert_nil opening.description
  end

  test "the opening location is the story's opening_location" do
    story = generate_with(FakeAgent.new(CONTENT))

    assert_equal story.locations.first, story.opening_location
  end

  test "saving the universe persists the story and its opening location" do
    story = generate_with(FakeAgent.new(CONTENT))
    @universe.save!

    assert story.persisted?
    assert story.opening_location.persisted?
    assert_equal story, story.opening_location.story
  end

  test "strips emoji from the opening location too" do
    agent = FakeAgent.new(CONTENT.merge("opening_location_name" => "The Drowned Ledger 🌊"))

    assert_equal "The Drowned Ledger", generate_with(agent).opening_location.name
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
    story = generate_with(FakeAgent.new(CONTENT))

    assert story.new_record?
    assert story.opening_location.new_record?
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
