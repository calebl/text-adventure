require "test_helper"

class Character::GeneratorTest < ActiveSupport::TestCase
  SHEET = {
    "fullname" => "Ember Lacroix",
    "nickname" => "Cinder",
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

  test "assigns every character attribute from the one response" do
    character = generate_with(FakeAgent.new(SHEET))

    assert_equal "Ember Lacroix", character.fullname
    assert_equal "Cinder", character.nickname
    assert_equal "Watchful and slow to speak.", character.personality
    assert_equal "Salt-bleached coat, chalk on the knuckles.", character.appearance
    assert_equal "Low tide, quiet, strong tea", character.likes
    assert_equal "Debts, bells, being asked twice", character.dislikes
    assert_equal "The Grief taking someone they love", character.fears
    assert_equal "Raised inland, sent to the coast after a family disgrace.", character.backstory
  end

  # These three are the generator's to decide, not the model's. The prompt
  # states all three, so asking the schema for them too bought them twice.
  test "assigns the rolled age and sex rather than asking for them" do
    generator = Character::Generator.new(@story)
    character = BaseAgent.stub(:new, FakeAgent.new(SHEET)) { generator.generate }

    assert_equal generator.age, character.age
    assert_equal Character.sexes.key(generator.sex), character.sex
  end

  # The roll now decides `sex` outright -- there is no schema enum narrowing it
  # afterwards -- so every value it can produce has to be one Character stores.
  test "every sex it can roll is one Character accepts" do
    20.times do
      sex = Character::Generator.new(@story).sex

      assert_includes Character.sexes.values, sex
      assert Character.sexes.key(sex).present?, "#{sex} has no enum key"
    end
  end

  test "states the rolled age and sex in the prompt" do
    generator = Character::Generator.new(@story)

    assert_includes generator.character_generation_prompt, "age: #{generator.age}"
    assert_includes generator.character_generation_prompt, "sex: #{generator.sex}"
  end

  # Race is picked from the universe rather than invented, which is what keeps
  # characters inside the setting the universe established.
  test "assigns a race drawn from the story's universe" do
    character = generate_with(FakeAgent.new(SHEET))

    assert_includes @story.universe.races, character.race
  end

  test "generates a valid character" do
    assert generate_with(FakeAgent.new(SHEET)).valid?
  end

  test "does not persist the character" do
    assert generate_with(FakeAgent.new(SHEET)).new_record?
  end

  test "belongs to the story it was generated for" do
    assert_equal @story, generate_with(FakeAgent.new(SHEET)).story
  end

  test "asks once, for the whole character sheet" do
    agent = FakeAgent.new(SHEET)
    generate_with(agent)

    assert_equal [ Character::Schema ], agent.schemas
    assert_equal 1, agent.prompts.count
  end

  test "does not ask the model to invent a race, an age or a sex" do
    assert_equal [], %i[race age sex] & Character::Schema.required_properties
  end

  # The backstory seed used to arrive on a second prompt of its own. It is a
  # constraint on one field, not a call's worth of work.
  test "seeds the backstory in the one prompt" do
    generator = Character::Generator.new(@story)

    assert_includes generator.character_generation_prompt, "born in a:"
    assert_includes generator.character_generation_prompt, "raised by:"
    assert_includes generator.character_generation_prompt, "backstory covers their life before the story"
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
    character = generate_with(FakeAgent.new(SHEET.merge("fullname" => "Ember Lacroix 🔥")))

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
