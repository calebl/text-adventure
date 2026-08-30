require "test_helper"

class Character::GeneratorTest < ActiveSupport::TestCase
  BASE = {
    "fullname" => "Ember Lacroix",
    "nickname" => "Cinder",
    "age" => 32,
    "sex" => "non-binary"
  }.freeze

  BACKGROUND = {
    "personality" => "Watchful and slow to speak.",
    "appearance" => "Salt-bleached coat, chalk on the knuckles.",
    "likes" => "Low tide, quiet, strong tea",
    "dislikes" => "Debts, bells, being asked twice",
    "fears" => "The Grief taking someone they love",
    "backstory" => "Raised inland, sent to the coast after a family disgrace."
  }.freeze

  def setup
    @story = create(:story)
  end

  def generate_with(agent)
    BaseAgent.stub(:new, agent) do
      Character::Generator.new(@story).generate
    end
  end

  test "assigns every character attribute from the two responses" do
    character = generate_with(FakeAgent.new(BASE, BACKGROUND))

    assert_equal "Ember Lacroix", character.fullname
    assert_equal "Cinder", character.nickname
    assert_equal 32, character.age
    assert_equal "non_binary", character.sex  # enum key for the "non-binary" value
    assert_equal "Watchful and slow to speak.", character.personality
    assert_equal "Raised inland, sent to the coast after a family disgrace.", character.backstory
  end

  # Race is picked from the universe rather than invented, which is what keeps
  # characters inside the setting the universe established.
  test "assigns a race drawn from the story's universe" do
    character = generate_with(FakeAgent.new(BASE, BACKGROUND))

    assert_includes @story.universe.races, character.race
  end

  test "generates a valid character" do
    assert generate_with(FakeAgent.new(BASE, BACKGROUND)).valid?
  end

  test "does not persist the character" do
    assert generate_with(FakeAgent.new(BASE, BACKGROUND)).new_record?
  end

  test "belongs to the story it was generated for" do
    assert_equal @story, generate_with(FakeAgent.new(BASE, BACKGROUND)).story
  end

  test "asks for the base schema then the background schema" do
    agent = FakeAgent.new(BASE, BACKGROUND)
    generate_with(agent)

    assert_equal [ Character::BaseSchema, Character::BackgroundSchema ], agent.schemas
  end

  test "does not ask the model to invent a race" do
    assert_not_includes Character::BaseSchema.required_properties, :race
  end

  test "names the chosen race in the prompt so the model writes to it" do
    generator = Character::Generator.new(@story)

    assert_includes generator.character_generation_prompt, generator.race.name
  end

  test "includes the universe details in the prompt" do
    generator = Character::Generator.new(@story)

    assert_includes generator.character_generation_prompt, @story.universe.politics
  end

  test "strips emoji from generated text" do
    character = generate_with(FakeAgent.new(BASE.merge("fullname" => "Ember Lacroix 🔥"), BACKGROUND))

    assert_equal "Ember Lacroix", character.fullname
  end

  test "raises when the model call fails" do
    failing = Object.new
    def failing.with_instructions(_) = self
    def failing.with_schema(_) = self
    def failing.ask(_) = raise(RubyLLM::Error.new(nil, "boom"))

    assert_raises(RubyLLM::Error) { generate_with(failing) }
  end
end
