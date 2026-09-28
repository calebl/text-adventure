require "test_helper"

# ONE EXCHANGE, TWO PASSES, AND BOTH REQUESTS ARE THE ENGINE'S.
#
# `Playthrough::Turn#converse` asks the *character* what they thought, felt and
# did, under the interaction schema, and hands that structured answer to a
# schema-free *narrator* which turns it into second-person prose. The words of
# both requests are the engine's (`dialogue::character_request`,
# `dialogue::narrator_request`, through `Playthrough::Requests`); what this file
# pins is the hand-off between the passes, the sanitizing seam in front of the
# record, the rotation a truncated sheet costs, the streaming, and what the
# engine's prompts say.
#
# Both passes go through BaseAgent, so both inherit its model fallback and the
# first inherits verify_schema_honored!. FakeAgent stands in at that boundary.
class Playthrough::TurnExchangeTest < ActiveSupport::TestCase
  CHARACTER_RESPONSE = {
    "pre_thought" => "Is that person talking to me?",
    "pre_feeling" => "surprised, wary",
    "action" => "She sets down the crate and squares her shoulders.",
    "post_feeling" => "steadier",
    "post_thought" => "Say something before this gets strange.",
    "inner_resolution" => "She will hear this stranger out before deciding anything.",
    "engine_action" => "none"
  }.freeze

  setup do
    @story = create(:story)
    @room = create(:location, story: @story, description: "A counting room gone to damp.")
    @protagonist = create(:character, :protagonist, story: @story, fullname: "Odile Vance", nickname: "Vance")
    @character = create(:character, story: @story, location: @room, fullname: "Mira Halloway", nickname: "Mira",
                                    sex: "female")
    @game = create(:playthrough, story: @story, character: @protagonist, current_location: @room)
  end

  # --- the two passes -------------------------------------------------------

  test "the character pass asks under the interaction schema, with the engine's instructions" do
    _, character, = interact

    assert_equal 1, character.schemas.size
    assert_equal Interaction::Schema.with_actions(Playthrough::NpcAction.new(@game, @character).choices.keys).new.to_json_schema,
                 character.schemas.last.new.to_json_schema
    assert_equal character_request.fetch("system"), character.instructions
    assert_match(/Mira Halloway/, character.instructions)
  end

  # The second pass is prose, so it must NOT carry a schema -- a narrator
  # constrained to the interaction schema would answer with JSON.
  test "the narrator pass is unconstrained by any schema and carries no sheet" do
    _, _, narrator = interact

    assert_empty narrator.schemas
    assert_nil narrator.instructions
  end

  test "makes exactly two calls, the character and then the narrator, on two agents" do
    _, character, narrator = interact

    assert_not_same character, narrator
    assert_equal 1, character.prompts.count
    assert_equal 1, narrator.prompts.count
  end

  test "asks the character about the raw typed line" do
    _, character, = interact

    assert_includes character.prompts.first, "Excuse me?"
  end

  test "hands every structured field from the first pass to the second" do
    _, _, narrator = interact
    prompt = narrator.prompts.first

    CHARACTER_RESPONSE.except("inner_resolution", "engine_action").each_value { |value| assert_includes prompt, value }
    assert_includes prompt, "Excuse me?"
  end

  # THE ONE FIELD THE NARRATOR IS NOT TOLD. A resolution is about what the
  # character will do next; handing it to the pass that writes the moment
  # invites it to narrate them acting on a decision the player has not seen.
  test "the character's resolution is kept, not narrated" do
    exchange, _, narrator = interact

    assert_equal CHARACTER_RESPONSE["inner_resolution"], exchange.reaction[:inner_resolution]
    assert_not_includes narrator.prompts.first, CHARACTER_RESPONSE["inner_resolution"]
    assert_not_includes narrator.prompts.first, "inner_resolution"
  end

  # --- what comes back ------------------------------------------------------

  test "returns both the prose and the character's structured reaction" do
    exchange, = interact(narration: "Mira sets down the crate and looks up at you.")

    assert_equal "Mira sets down the crate and looks up at you.", exchange.narration
    assert_equal CHARACTER_RESPONSE.except("engine_action").transform_keys(&:to_sym), exchange.reaction
  end

  test "the reaction is keyed as Interaction::Schema names its fields" do
    exchange, = interact

    assert_equal Interaction::Schema.required_properties.map(&:to_sym).sort, exchange.reaction.keys.sort
    assert Interaction.new(exchange.reaction.merge(character: @character)).valid?
  end

  # A FIELD THE MODEL OMITTED IS BLANK, and a blank reaction is not an
  # interaction the game keeps: it fails inside the call, so the next model is
  # asked.
  test "a field the model omitted fails the exchange rather than being kept blank" do
    assert_raises(ActiveRecord::RecordInvalid) { interact(reaction: { "action" => "She shrugs." }) }
  end

  # --- the sanitizing seam --------------------------------------------------

  test "the character's fields go through the sanitizer" do
    exchange, = interact(reaction: CHARACTER_RESPONSE.merge(
      "pre_feeling" => "surprised, wary \u{1F30A}",
      "post_thought" => %(Say something.\u{201D}})
    ))

    assert_equal "surprised, wary", exchange.reaction[:pre_feeling]
    assert_equal "Say something.", exchange.reaction[:post_thought]
  end

  # A `pre_feeling` once came back at exactly its cap ending "hopeful for a
  # (v"; the narrator pass wrote fluent prose over the fragment, so the record
  # kept half a word and the player read a whole sentence. The turn fails now.
  test "a field truncated at its cap fails the exchange before the narrator is asked" do
    cap = Interaction::Schema.max_length_for(:pre_feeling)
    cut = "wary, guarded, hopeful for a (v".ljust(cap, "e")
    character = FakeAgent.new(CHARACTER_RESPONSE.merge("pre_feeling" => cut))
    narrator = FakeAgent.new("Mira looks up.")

    with_agents(character, narrator) do
      assert_raises(SanitizesGeneratedText::TruncatedTextError) { converse }
    end
    assert_equal 1, character.prompts.count
    assert_empty narrator.prompts
  end

  test "every one of the reaction's fields is checked against its own cap" do
    Interaction::Schema.required_properties.each do |field|
      cap = Interaction::Schema.max_length_for(field)

      assert_raises(SanitizesGeneratedText::TruncatedTextError, "#{field} is unguarded") do
        interact(reaction: CHARACTER_RESPONSE.merge(field.to_s => "a" * cap))
      end
    end
  end

  # --- a truncated sheet is a failed call, so it rotates ---------------------

  # A REAL BaseAgent for the character pass, because the rotation is the thing
  # asserted and a fake has no models to rotate through. On plain minimax a
  # truncated field once raised straight past the rotation on 15 of 16
  # narrations; the cost of an overrun is now one wasted call.
  test "a truncated character sheet costs a call, and the next model writes the turn" do
    truncated = CHARACTER_RESPONSE.merge(
      "pre_thought" => "She wondered whether to answer at all, so as not to r"
        .ljust(Interaction::Schema.max_length_for(:pre_thought), "e")
    )
    chat = ScriptedChat.new(truncated, CHARACTER_RESPONSE)
    narrator = FakeAgent.new("Mira looks up at you.")
    character = real_agent(chat)

    exchange = with_agents(character, narrator) { converse }

    assert_equal 2, chat.attempts, "the truncated sheet cost a call rather than the turn"
    assert_equal "second-model", character.current_model[:model], "and the rotation happened"
    assert_equal CHARACTER_RESPONSE["pre_thought"], exchange.reaction[:pre_thought]
    assert_equal 1, narrator.prompts.count, "the narrator was paid for once, for the good sheet"
    assert_not_includes narrator.prompts.first, truncated["pre_thought"]
  end

  test "a truncation every model commits still fails the exchange" do
    cut = "a" * Interaction::Schema.max_length_for(:action)
    chat = ScriptedChat.new(*Array.new(3) { CHARACTER_RESPONSE.merge("action" => cut) })

    with_agents(real_agent(chat), FakeAgent.new("Mira looks up at you.")) do
      assert_raises(SanitizesGeneratedText::TruncatedTextError) { converse }
    end
    assert_equal 2, chat.attempts, "two models, so two attempts"
  end

  # --- streaming ------------------------------------------------------------

  test "a block publishes only the verified narration" do
    chunks = []

    with_agents(FakeAgent.new(CHARACTER_RESPONSE), FakeAgent.new("Mira looks up at you.")) do
      converse { |chunk| chunks << chunk }
    end

    assert_equal "Mira looks up at you.", chunks.join
    assert_equal 1, chunks.count
  end

  # --- the engine's narrator prompt ----------------------------------------

  test "the narrator prompt asks for second person prose about the character" do
    prompt = narrator_prompt

    assert_match(/second person/, prompt)
    assert_match(/The player is "you"/, prompt)
    assert_match(/Refer to the character as Mira\./, prompt)
    assert_match(/One or two short paragraphs/, prompt)
  end

  test "the narrator prompt confines the narrator to the reaction and the exchange" do
    prompt = narrator_prompt

    assert_match(/Everything you know about Mira is the reaction above and the exchange itself/, prompt)
    assert_match(/Do not add facts about Mira/, prompt)
    assert_no_match(/backstory/, prompt, "it has no backstory to be told about")
    assert_no_match(/the user/i, prompt, "the player is never 'the user'")
  end

  test "the narrator prompt keeps the prose on the moment" do
    prompt = narrator_prompt

    assert_match(/do not narrate what\s+she will do next/, prompt)
    assert_match(/do not end on a question to them/, prompt)
  end

  test "the narrator prompt reads missing structured fields as blank" do
    prompt = narrator_prompt(reaction: {})

    assert_match(/^pre_thought:\s*$/, prompt)
    assert_match(/^action:\s*$/, prompt)
  end

  # `Character#sex` is an enum and reads back its KEY, so the prompt states the
  # pronouns instead of asking the model to infer them, for every value
  # `Character::Generator` can roll.
  test "the narrator is told which pronouns to use, for every sex" do
    assert_equal Character.sexes.keys.sort, Character::PRONOUNS.keys.sort

    Character::PRONOUNS.each do |sex, pronouns|
      character = create(:character, story: @story, location: @room, sex: sex)
      prompt = narrator_prompt(character: character)

      assert_match(/Refer to #{character.fullname} as #{Regexp.escape(pronouns)}\./, prompt)
      assert_no_match(/is a #{sex}/, prompt)
    end
  end

  test "the narrator is never told that a character is trans" do
    %w[trans_woman trans_man].each do |sex|
      prompt = narrator_prompt(character: create(:character, story: @story, location: @room, sex: sex))
      assert_no_match(/\btrans\b|trans_|transgender/i, prompt)
    end
  end

  # THE EXAMPLE IS THE CHARACTER'S OWN, name and pronouns, verbs agreeing.
  test "the worked example uses the character's own name and pronouns" do
    prompt = narrator_prompt

    assert_match(/Mira turns to you, her eyes wide\. It seems you startled her\./, prompt)
    assert_match(/"Huh\?" she says\./, prompt)
  end

  test "the worked example agrees its verbs with they/them and uses he/him for a man" do
    sam = create(:character, story: @story, location: @room, fullname: "Sam Reyes", nickname: "Sam", sex: "non_binary")
    tom = create(:character, story: @story, location: @room, fullname: "Tomas Hale", nickname: "Tom", sex: "trans_man")

    assert_match(/Sam turns to you, their eyes wide\. It seems you startled them\./, narrator_prompt(character: sam))
    assert_match(/"Huh\?" they say\./, narrator_prompt(character: sam))
    assert_match(/Tom turns to you, his eyes wide\. It seems you startled him\./, narrator_prompt(character: tom))
  end

  test "the narrator pass asks for the same length as the narrator" do
    assert_match(/one or two short paragraphs/i, narrator_prompt)
    assert_match(/one or two short paragraphs/i, Playthrough::PromptVersion.narrator_instructions)
  end

  # --- the moment, in both passes -------------------------------------------

  test "the character pass is told the moment and who is speaking" do
    prompt = character_request.fetch("user")

    assert_match(/## The moment/, prompt)
    assert_match(/Where you are: #{Regexp.escape(@room.name)}\./, prompt)
    assert_match(/The time is about/, prompt)
    assert_match(/## What Odile Vance says or does\nExcuse me\?/, prompt)
    assert_match(/React as Mira Halloway/, prompt)
    assert_no_match(/user/i, prompt)
  end

  test "the narrator pass is told where the exchange happens" do
    prompt = narrator_prompt

    assert_match(/## Where this happens/, prompt)
    assert_match(/A counting room gone to damp\./, prompt)
    assert_match(/Ways out of here/, prompt)
    assert_match(/Odile Vance says or does: Excuse me\?/, prompt)
    assert_match(/Add nobody who is not listed above/, prompt)
  end

  # AND IT DOES NOT GET THE FLOOR PLAN, which is a decision rather than an
  # omission (`Location::Plan`'s header): geometry reaches the room writer and
  # the narrator, whose prompts are measured, and not this pass.
  test "the narrator pass is not told the room's floor plan, and the narrator is" do
    place = create(:location, :stub, story: @story, name: "The Custom House", width: 14, depth: 10)
    room = create(:location, :stub, story: @story, name: "the back room", parent_location: place,
                                    x: 0, y: 0, z: 0, width: 7, depth: 6, description: "Ledgers to the ceiling.")
    @game.update!(current_location: room)
    @character.move_to!(room)

    prompt = narrator_prompt
    assert_match(/## Where this happens/, prompt)
    assert_match(/Ledgers to the ceiling\./, prompt, "it still gets the moment")
    assert_no_match(/paces/, prompt)
    assert_no_match(/storey/, prompt)
    assert_includes EngineMoment.new(@game).narration_context, Location::Plan.for(room).to_prompt,
                    "the narrator still carries it"
  end

  private

  def converse(&block) = Playthrough::Turn.new(@game).converse(@character, "Excuse me?", &block)

  # Runs the exchange with a fake per pass; answers [exchange, character, narrator].
  def interact(reaction: CHARACTER_RESPONSE, narration: "Mira looks up at you.")
    character = FakeAgent.new(reaction)
    narrator = FakeAgent.new(narration)
    [ with_agents(character, narrator) { converse }, character, narrator ]
  end

  # Hands out the two agents in construction order: character first, narrator
  # second.
  def with_agents(character, narrator, &)
    queued = [ character, narrator ]
    BaseAgent.stub(:new, ->(*, **) { queued.shift }, &)
  end

  def character_request(character: @character, line: "Excuse me?")
    Playthrough::Requests.build(:character, playthrough: @game.id, character: character.id, line: line)
  end

  def narrator_prompt(character: @character, reaction: CHARACTER_RESPONSE, line: "Excuse me?")
    Playthrough::Requests.build(:interaction_narration, playthrough: @game.id, character: character.id, line: line,
                                                        reaction: reaction, fact: "Nothing changed hands.")
                         .fetch("user")
  end

  TWO_MODELS = [
    { provider: :ollama, model: "first-model", assume_model_exists: true },
    { provider: :ollama, model: "second-model", assume_model_exists: true }
  ].freeze

  # A real BaseAgent over a scripted chat, for the tests about the ROTATION.
  def real_agent(chat)
    agent = BaseAgent.new(model_options: TWO_MODELS)
    agent.instance_variable_set(:@chat, chat)
    agent
  end

  # Answers each attempt with the next scripted content, so a rotation can be
  # seen from the chat's side. Enough of RubyLLM::Chat's surface for BaseAgent.
  class ScriptedChat
    attr_reader :attempts

    def initialize(*contents)
      @contents = contents
      @attempts = 0
    end

    def with_instructions(_instructions) = self
    def with_schema(_schema) = self
    def with_model(_model, **_options) = self

    def ask(_prompt)
      @attempts += 1
      Struct.new(:content).new(@contents.shift)
    end
  end
end
