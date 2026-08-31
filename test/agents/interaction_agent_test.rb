require "test_helper"

# InteractionAgent is deliberately two-pass. The first pass asks the *character*
# what they thought, felt and did, under Interaction::Schema. The second hands
# that structured answer to a plain, schema-free *narrator* chat which turns it
# into second-person prose. Neither pass is useful without the other, and the
# hand-off between them is by string key, so it is the seam worth pinning.
#
# Note: this class builds its own RubyLLM::Chat objects rather than going
# through BaseAgent, so it gets none of BaseAgent's model rotation or
# schema-honored checking. That is a known gap owned by a roadmap item, not
# something these tests assert away.
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

  test "opens the character chat under the interaction schema" do
    build_agent { assert_equal Interaction::Schema, character_chat.schema }
  end

  test "instructs the character chat with the character's own sheet" do
    build_agent do |agent|
      assert_equal @character.interaction_instructions, agent.character_instructions
      assert_equal @character.interaction_instructions, character_chat.instructions
      assert_match(/Mira Halloway/, character_chat.instructions)
    end
  end

  test "asks a remote model that is assumed to exist" do
    build_agent do
      assert_equal :openrouter, character_chat.constructor_options[:provider]
      assert character_chat.constructor_options[:assume_model_exists]
      assert character_chat.constructor_options[:model].present?
    end
  end

  test "makes exactly two calls: the character, then the narrator" do
    interact do
      assert_equal 2, FakeChat.built.count
      assert_equal 1, character_chat.prompts.count
      assert_equal 1, narrator_chat.prompts.count
    end
  end

  test "passes the raw user input to the character, unwrapped" do
    interact { assert_equal [ "Excuse me?" ], character_chat.prompts }
  end

  test "returns the narrator's prose, not the character's structured answer" do
    interact(narration: "Mira sets down the crate and looks up at you.") do |narration|
      assert_equal "Mira sets down the crate and looks up at you.", narration
    end
  end

  # The second pass is prose, so it must NOT carry a schema -- a narrator
  # constrained to Interaction::Schema would answer with JSON.
  test "the narrator pass is unconstrained by any schema" do
    interact { assert_nil narrator_chat.schema }
  end

  test "the narrator pass is a fresh chat, not the character's" do
    interact do
      assert_not_same character_chat, narrator_chat
      assert_nil narrator_chat.instructions
    end
  end

  test "hands every structured field from the first pass to the second" do
    interact do
      prompt = narrator_chat.prompts.first

      CHARACTER_RESPONSE.each_value do |value|
        assert_includes prompt, value
      end
    end
  end

  test "the narrator prompt echoes the user input" do
    interact { assert_includes narrator_chat.prompts.first, "Excuse me?" }
  end

  # KNOWN WART, pinned rather than fixed here (agent changes are out of scope
  # for the RubyLLM upgrade). `attr_reader :narrator_instructions` on line 2 is
  # shadowed by the two-argument `def narrator_instructions` below it, so the
  # `@narrator_instructions` the agent assigns during `ask` is unreachable --
  # calling the reader re-enters the builder and raises on arity instead.
  test "the narrator_instructions reader is shadowed by the builder method" do
    interact do |_, agent|
      assert_raises(ArgumentError) { agent.narrator_instructions }
      assert_equal narrator_chat.prompts.first, agent.instance_variable_get(:@narrator_instructions)
    end
  end

  test "narrator_instructions asks for second person prose about the character" do
    build_agent do |agent|
      prompt = agent.narrator_instructions("Excuse me?", CHARACTER_RESPONSE)

      assert_match(/second person/, prompt)
      assert_match(/Refer to the user as "you"/, prompt)
      assert_match(/first name or nickname/, prompt)
      assert_match(/1 paragraph/, prompt)
    end
  end

  test "narrator_instructions carries the character's gender for pronoun choice" do
    build_agent do |agent|
      prompt = agent.narrator_instructions("Excuse me?", CHARACTER_RESPONSE)

      assert_match(/Mira Halloway is a female/, prompt)
      assert_match(%r{she/her/her}, prompt)
    end
  end

  # KNOWN WART, pinned rather than fixed here. `Character#sex` is an
  # ActiveRecord enum, so it reads back as the enum *key* -- the prompt says
  # "is a non_binary" while the pronoun rule two lines later is keyed on
  # "non-binary". Same for transgender, which has no pronoun rule at all.
  # Worth fixing; not in this PR's scope.
  test "narrator_instructions interpolates the enum key, not the stored value" do
    @character = create(:character, fullname: "Ash Vane", sex: "non_binary")

    build_agent do |agent|
      prompt = agent.narrator_instructions("Excuse me?", CHARACTER_RESPONSE)

      assert_match(/Ash Vane is a non_binary/, prompt)
      assert_match(%r{they/them/their}, prompt)
      assert_equal "non-binary", @character.class.sexes.fetch("non_binary")
    end
  end

  # The character sheet already went to the character chat as instructions.
  # Repeating the backstory to the narrator invites it to recite biography
  # instead of narrating the moment.
  test "narrator_instructions forbids restating the backstory" do
    build_agent do |agent|
      prompt = agent.narrator_instructions("Excuse me?", CHARACTER_RESPONSE)

      assert_match(/Do not respond with details of the character's/, prompt)
      assert_match(/Do not make up information/, prompt)
    end
  end

  test "narrator_instructions reads missing structured fields as blank" do
    build_agent do |agent|
      prompt = agent.narrator_instructions("Excuse me?", {})

      assert_match(/^pre_thought:\s*$/, prompt)
      assert_match(/^action:\s*$/, prompt)
    end
  end

  private

  # Builds the agent with RubyLLM::Chat faked, and keeps the fake installed for
  # the duration of the block -- the narrator chat is not constructed until
  # `ask` runs, so the stub has to outlive the constructor.
  def build_agent(character: CHARACTER_RESPONSE, narration: "Mira looks up at you.")
    FakeChat.with_fake_chats([ character ], [ narration ]) do
      yield InteractionAgent.new(@character)
    end
  end

  # Runs a full two-pass exchange and yields (narration, agent).
  def interact(narration: "Mira looks up at you.", input: "Excuse me?")
    build_agent(narration: narration) do |agent|
      yield agent.ask(input), agent
    end
  end

  def character_chat = FakeChat.built.first
  def narrator_chat = FakeChat.built.second
end
