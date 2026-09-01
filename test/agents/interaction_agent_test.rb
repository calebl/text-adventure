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
    "post_thought" => "Say something before this gets strange.",
    "inner_resolution" => "She will hear this stranger out before deciding anything."
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

    CHARACTER_RESPONSE.except("inner_resolution").each_value { |value| assert_includes prompt, value }
    assert_includes prompt, "Excuse me?"
  end

  # THE ONE FIELD THE NARRATOR IS NOT TOLD. A resolution is about what the
  # character will do next; handing it to the pass that writes the moment invites
  # it to narrate them acting on a decision the player has not seen them make.
  # It is kept on the Interaction, which is what `#completed?` reads.
  test "the character's resolution is kept, not narrated" do
    agent = interact.last

    assert_not_includes agent.narrator_agent.prompts.first, CHARACTER_RESPONSE["inner_resolution"]
    assert_not_includes agent.narrator_agent.prompts.first, "inner_resolution"
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

  # --- the sanitizing seam --------------------------------------------------

  # The talk path used to be the one generated-string path in the app that did
  # not pass through SanitizesGeneratedText, so none of its guards applied to
  # the six fields a conversation writes every turn.
  test "the character's fields go through the sanitizer" do
    exchange, = interact(character: CHARACTER_RESPONSE.merge(
      "pre_feeling" => "surprised, wary \u{1F30A}",
      "post_thought" => %(Say something.\u{201D}})
    ))

    assert_equal "surprised, wary", exchange.reaction[:pre_feeling]
    assert_equal "Say something.", exchange.reaction[:post_thought]
  end

  # WAS SILENT, AND THAT WAS THE BUG. A `pre_feeling` came back at exactly its
  # cap ending "hopeful for a (v"; the narrator pass wrote fluent prose over the
  # fragment, so the record kept half a word and the player read a whole
  # sentence. The turn fails now instead.
  test "a field truncated at its cap fails the exchange rather than being kept" do
    cap = Interaction::Schema.max_length_for(:pre_feeling)
    cut = "wary, guarded, hopeful for a (v".ljust(cap, "e")

    assert_raises(SanitizesGeneratedText::TruncatedTextError) do
      interact(character: CHARACTER_RESPONSE.merge("pre_feeling" => cut))
    end
  end

  # Caught BEFORE the narrator is paid for, and before any prose exists for the
  # player to have read: the narrator's whole job is to paper over what it is
  # handed, so it must never be handed a fragment.
  test "a truncated field is caught before the narrator pass runs" do
    cap = Interaction::Schema.max_length_for(:pre_thought)
    cut = "She wondered whether to answer at all, so as not to r".ljust(cap, "e")

    stub_agents(CHARACTER_RESPONSE.merge("pre_thought" => cut), "Mira looks up.") do |agent|
      assert_raises(SanitizesGeneratedText::TruncatedTextError) { agent.ask("Excuse me?") }
      assert_equal 1, agent.character_agent.prompts.count
      assert_empty agent.narrator_agent.prompts
    end
  end

  # Every field, not only the two that were caught in real data.
  test "every one of the six fields is checked against its own cap" do
    Interaction::Schema.required_properties.each do |field|
      cap = Interaction::Schema.max_length_for(field)

      assert_raises(SanitizesGeneratedText::TruncatedTextError, "#{field} is unguarded") do
        interact(character: CHARACTER_RESPONSE.merge(field.to_s => "a" * cap))
      end
    end
  end

  # The caps have to leave room for the shape the schema asks for, or the guard
  # fires on answers that were never truncated. A full, ordinary reaction passes.
  test "an ordinary reaction is nowhere near its caps" do
    exchange, = interact

    assert_equal CHARACTER_RESPONSE.transform_keys(&:to_sym), exchange.reaction
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
  # Character::Generator rolls sex from every Character.sexes value. The prompt
  # now states the pronouns instead of asking the model to infer them, and reads
  # them off `Character::PRONOUNS` -- pronouns are a fact about the person, not
  # about this agent.
  test "the narrator is told which pronouns to use, for every sex" do
    # Every value Character::Generator can roll has an entry, so no sex can
    # reach the prompt with no pronouns of its own. CharacterTest pins the same
    # thing at the table; this pins that the prompt actually says it.
    assert_equal Character.sexes.keys.sort, Character::PRONOUNS.keys.sort

    Character::PRONOUNS.each do |sex, pronouns|
      character = create(:character, sex: sex)
      prompt = InteractionAgent.new(character).narrator_prompt("Hello?", CHARACTER_RESPONSE)

      assert_match(/Refer to #{character.fullname} as #{Regexp.escape(pronouns)}\./, prompt)
      assert_no_match(/is a #{sex}/, prompt)
    end
  end

  # `transgender` was one value standing in for two different people, and it got
  # they/them -- which is wrong for both of them. A trans woman is a woman and a
  # trans man is a man, so each takes exactly what any other woman or man takes.
  test "a trans woman and a trans man get the same pronouns as any other woman or man" do
    assert_equal Character::PRONOUNS.fetch("female"), Character::PRONOUNS.fetch("trans_woman")
    assert_equal Character::PRONOUNS.fetch("male"), Character::PRONOUNS.fetch("trans_man")
  end

  # The narrator needs the pronouns; it does not need to be told a character is
  # trans, any more than it is told that a character is cis. The prompt states
  # the pronouns and no gender label at all, so there is nothing here to leak.
  test "the narrator is never told that a character is trans" do
    %w[trans_woman trans_man].each do |sex|
      character = create(:character, sex: sex)
      prompt = InteractionAgent.new(character).narrator_prompt("Hello?", CHARACTER_RESPONSE)

      assert_no_match(/trans/i, prompt)
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

    # Splatted: BaseAgent takes the keywords that decide where the conversation
    # is filed (purpose, playthrough, character, chat), and the fake ignores them.
    BaseAgent.stub(:new, ->(*, **) { queued.shift }) do
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
