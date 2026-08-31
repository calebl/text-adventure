require "test_helper"

# InteractionAgent is deliberately two-pass. The first pass asks the *character*
# what they thought, felt and did, under Interaction::Schema. The second hands
# that structured answer to a schema-free *narrator* which turns it into
# second-person prose. Neither pass is useful without the other, and the
# hand-off between them is by string key, so it is the seam worth pinning.
#
# Both passes now go through BaseAgent, so both inherit its model fallback and
# the first inherits verify_schema_honored!. FakeAgent stands in at that
# boundary, which is also why the model ids this class used to hardcode --
# `cognitivecomputations/dolphin-mixtral-8x22b`, which resolves nowhere -- are
# gone from these tests along with the code.
class InteractionAgentTest < ActiveSupport::TestCase
  CHARACTER_RESPONSE = {
    "pre_thought" => "Is that person talking to me?",
    "pre_feeling" => "surprised, wary",
    "action" => "She sets down the crate and squares her shoulders.",
    "post_feeling" => "steadier",
    "post_thought" => "Say something before this gets strange."
  }.freeze

  setup do
    @character = create(:character, fullname: "Mira Halloway", nickname: "Mira", sex: "female")
  end

  # --- the two passes -------------------------------------------------------

  test "the character pass asks under the interaction schema, with their own sheet" do
    agent = build_agent

    assert_equal Interaction::Schema, agent.character_agent.schemas.last
    assert_equal @character.interaction_instructions, agent.character_agent.instructions
    assert_match(/Mira Halloway/, agent.character_agent.instructions)
  end

  # The second pass is prose, so it must NOT carry a schema -- a narrator
  # constrained to Interaction::Schema would answer with JSON.
  test "the narrator pass is unconstrained by any schema and carries no sheet" do
    agent = build_agent

    assert_empty agent.narrator_agent.schemas
    assert_nil agent.narrator_agent.instructions
  end

  test "the narrator pass is a fresh agent, not the character's" do
    agent = build_agent

    assert_not_same agent.character_agent, agent.narrator_agent
  end

  test "makes exactly two calls: the character, then the narrator" do
    agent = interact.last

    assert_equal 1, agent.character_agent.prompts.count
    assert_equal 1, agent.narrator_agent.prompts.count
  end

  test "asks the character about the raw user input" do
    agent = interact.last

    assert_includes agent.character_agent.prompts.first, "Excuse me?"
  end

  test "hands every structured field from the first pass to the second" do
    agent = interact.last
    prompt = agent.narrator_agent.prompts.first

    CHARACTER_RESPONSE.each_value { |value| assert_includes prompt, value }
    assert_includes prompt, "Excuse me?"
  end

  # --- what comes back ------------------------------------------------------

  # The old version returned the prose and threw the structured answer away,
  # which is why nothing in this app had ever created an Interaction row.
  test "returns both the prose and the character's structured reaction" do
    exchange, = interact(narration: "Mira sets down the crate and looks up at you.")

    assert_equal "Mira sets down the crate and looks up at you.", exchange.narration
    assert_equal CHARACTER_RESPONSE.transform_keys(&:to_sym), exchange.reaction
  end

  # Symbol keys, exactly the schema's field names, so the caller can splat it
  # straight into Interaction.create!.
  test "the reaction is keyed as Interaction::Schema names its fields" do
    exchange, = interact

    assert_equal Interaction::Schema.required_properties.map(&:to_sym).sort,
                 exchange.reaction.keys.sort
    assert Interaction.new(exchange.reaction.merge(character: @character)).valid?
  end

  test "a field the model omitted reads as blank rather than nil" do
    exchange, = interact(character: { "action" => "She shrugs." })

    assert_equal "She shrugs.", exchange.reaction[:action]
    assert_equal "", exchange.reaction[:pre_thought]
  end

  # --- streaming ------------------------------------------------------------

  # The narrator pass is prose the player watches arrive, which is the same
  # documented exception Scene::Narrator carries. The structured pass in front
  # of it must not reach the block.
  test "a block streams the narration only" do
    chunks = []

    stub_agents(CHARACTER_RESPONSE, "Mira looks up at you.") do |agent|
      agent.ask("Excuse me?") { |chunk| chunks << chunk }
    end

    assert_equal "Mira looks up at you.", chunks.join
    assert_operator chunks.count, :>, 1
  end

  # --- the narrator prompt --------------------------------------------------

  test "narrator_prompt asks for second person prose about the character" do
    prompt = build_agent.narrator_prompt("Excuse me?", CHARACTER_RESPONSE)

    assert_match(/second person/, prompt)
    assert_match(/Refer to the user as "you"/, prompt)
    assert_match(/first name or nickname/, prompt)
    assert_match(/1 paragraph/, prompt)
  end

  # The character sheet already went to the pass that needed it. Repeating the
  # backstory here invites the narrator to recite biography instead of
  # narrating the moment.
  test "narrator_prompt forbids restating the backstory" do
    prompt = build_agent.narrator_prompt("Excuse me?", CHARACTER_RESPONSE)

    assert_match(/Do not respond with details of the character's/, prompt)
    assert_match(/Do not make up information/, prompt)
  end

  test "narrator_prompt reads missing structured fields as blank" do
    prompt = build_agent.narrator_prompt("Excuse me?", {})

    assert_match(/^pre_thought:\s*$/, prompt)
    assert_match(/^action:\s*$/, prompt)
  end

  # --- pronouns -------------------------------------------------------------

  # WAS A BUG. `Character#sex` is an ActiveRecord enum, so it reads back the KEY
  # -- the prompt said "is a non_binary" while the rule two lines below keyed on
  # "non-binary", and `transgender` had no rule at all. Both are reachable:
  # Character::Generator rolls sex from all four Character.sexes values. The
  # prompt now states the pronouns instead of asking the model to infer them.
  test "the narrator is told which pronouns to use, for every sex" do
    # Every value Character::Generator can roll has an entry, so nothing falls
    # through to the default by accident.
    assert_equal Character.sexes.keys.sort, InteractionAgent::PRONOUNS.keys.sort

    InteractionAgent::PRONOUNS.each do |sex, pronouns|
      character = create(:character, sex: sex)
      prompt = InteractionAgent.new(character).narrator_prompt("Hello?", CHARACTER_RESPONSE)

      assert_match(/Refer to #{character.fullname} as #{Regexp.escape(pronouns)}\./, prompt)
      assert_no_match(/is a #{sex}/, prompt)
    end
  end

  # --- the reader that used to be unreachable -------------------------------

  # WAS A BUG. `attr_reader :narrator_instructions` was shadowed by a
  # two-argument method of the same name, so the value `ask` assigned could
  # never be read -- calling the reader re-entered the builder and raised on
  # arity. The builder is `narrator_prompt` now and the reader works.
  test "narrator_instructions reads back what the narrator was actually asked" do
    agent = interact.last

    assert_equal agent.narrator_agent.prompts.first, agent.narrator_instructions
  end

  private

  # FakeAgent per pass, handed out in construction order: character first,
  # narrator second. Returns the InteractionAgent, whose own readers expose
  # each fake.
  def stub_agents(character, narration)
    queued = [ FakeAgent.new(character), FakeAgent.new(narration) ]

    BaseAgent.stub(:new, -> { queued.shift }) do
      yield InteractionAgent.new(@character)
    end
  end

  def build_agent(character: CHARACTER_RESPONSE, narration: "Mira looks up at you.")
    stub_agents(character, narration) do |agent|
      # Touch both so the readers are memoized before the stub comes down.
      agent.character_agent
      agent.narrator_agent
      return agent
    end
  end

  # Runs a full two-pass exchange and returns [exchange, agent].
  def interact(character: CHARACTER_RESPONSE, narration: "Mira looks up at you.", input: "Excuse me?")
    stub_agents(character, narration) do |agent|
      return [ agent.ask(input), agent ]
    end
  end
end
