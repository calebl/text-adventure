require "test_helper"

class Universe::GeneratorTest < ActiveSupport::TestCase
  PHYSICAL = {
    "physics" => "Tides answer to a buried heartbeat.",
    "technology" => "Salvaged pumps and brass diving rigs.",
    "weapons" => "Gaff hooks and pressure lances.",
    "geographies" => "Nine tiers, the lowest three drowned."
  }.freeze

  SOCIETAL = {
    "races" => [
      { "name" => "Tidewalker", "description" => "Born to the flooded tiers, at home under water." },
      { "name" => "Dry-born", "description" => "Upper tier families who have never touched the Grief." }
    ],
    "civilizations" => "The Ledger Houses of the upper tiers.",
    "history" => "The god fell and the city grew on its back.",
    "economics" => "Debt is inherited and traded.",
    "politics" => "The Houses feud over drainage rights.",
    "religion" => "Worship of the corpse beneath."
  }.freeze

  def fake_agent(physical: PHYSICAL, societal: SOCIETAL)
    FakeAgent.new(physical, societal)
  end

  def generate_with(agent, premise: nil)
    BaseAgent.stub(:new, agent) do
      Universe::Generator.new(premise: premise).generate
    end
  end

  test "assigns every universe attribute from the two responses" do
    universe = generate_with(fake_agent)

    assert_equal "Tides answer to a buried heartbeat.", universe.physics
    assert_equal "Salvaged pumps and brass diving rigs.", universe.technology
    assert_equal "Gaff hooks and pressure lances.", universe.weapons
    assert_equal "Nine tiers, the lowest three drowned.", universe.geographies
    assert_equal [ "Tidewalker", "Dry-born" ], universe.races.map(&:name)
    assert_equal "The Ledger Houses of the upper tiers.", universe.civilizations
    assert_equal "The god fell and the city grew on its back.", universe.history
    assert_equal "Debt is inherited and traded.", universe.economics
    assert_equal "The Houses feud over drainage rights.", universe.politics
    assert_equal "Worship of the corpse beneath.", universe.religion
  end

  test "generates a valid universe" do
    assert generate_with(fake_agent).valid?
  end

  test "does not persist the universe" do
    assert generate_with(fake_agent).new_record?
  end

  test "asks for the physical schema then the societal schema" do
    agent = fake_agent
    generate_with(agent)

    assert_equal [ Universe::PhysicalSchema, Universe::SocietalSchema ], agent.schemas
  end

  test "includes the premise in the physical prompt" do
    agent = fake_agent
    generate_with(agent, premise: "a city built on a dead god")

    assert_includes agent.prompts.first, "a city built on a dead god"
  end

  test "falls back to letting the model choose when no premise is given" do
    agent = fake_agent
    generate_with(agent)

    assert_includes agent.prompts.first, "Your choice"
  end

  test "treats a blank premise as no premise" do
    assert_nil Universe::Generator.new(premise: "  ").premise
  end

  test "seeds a tone and era so repeated runs diverge" do
    generator = Universe::Generator.new

    assert_includes Universe::Generator::TONES, generator.tone
    assert_includes Universe::Generator::ERAS, generator.era
    assert_includes generator.physical_prompt, generator.tone
    assert_includes generator.physical_prompt, generator.era
  end

  test "strips emoji from generated text" do
    physical = PHYSICAL.merge("physics" => "Tides answer to a buried heartbeat. 🌊")
    universe = generate_with(fake_agent(physical: physical))

    assert_equal "Tides answer to a buried heartbeat.", universe.physics
  end

  test "builds a race record per generated race" do
    universe = generate_with(fake_agent)

    assert_equal 2, universe.races.size
    assert_equal "Born to the flooded tiers, at home under water.", universe.races.first.description
    assert universe.races.all?(&:new_record?)
  end

  test "strips emoji from race names and descriptions" do
    societal = SOCIETAL.merge("races" => [ { "name" => "Tidewalker 🌊", "description" => "At home under water. 🐟" } ])
    universe = generate_with(fake_agent(societal: societal))

    assert_equal "Tidewalker", universe.races.first.name
    assert_equal "At home under water.", universe.races.first.description
  end

  test "tolerates a response with no races rather than raising" do
    societal = SOCIETAL.merge("races" => nil)
    universe = generate_with(fake_agent(societal: societal))

    assert_empty universe.races
    assert_not universe.valid?
  end

  test "raises when the model call fails rather than returning a partial universe" do
    failing = Object.new
    def failing.with_instructions(_) = self
    def failing.with_schema(_) = self
    def failing.ask(_) = raise(RubyLLM::Error.new(nil, "boom"))

    assert_raises(RubyLLM::Error) { generate_with(failing) }
  end
end
