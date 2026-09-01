require "test_helper"

# THE POINT OF THE WHOLE CHANGE, tested at the seam where it lands: a turn's
# exchanges with a model become rows, and the rows are still there afterwards.
#
# `OfflineExchange` replaces only the HTTP call, so everything under test here
# is the real thing -- the real `BaseAgent`, real `Chat` and `Message` rows,
# real replay out of the database.
class ChatPersistenceTest < ActiveSupport::TestCase
  OPTIONS = [ { provider: :ollama, model: "gemma3:12b", assume_model_exists: true } ].freeze

  setup do
    @playthrough = create(:playthrough, :started)
  end

  # --- a conversation becomes rows ------------------------------------------

  test "asking writes the conversation, the prompt and the answer" do
    agent = BaseAgent.new("You narrate.", purpose: "narration",
                          playthrough: @playthrough, model_options: OPTIONS)

    OfflineExchange.with(OfflineExchange.reply("A road, and then the sea.", input: 210, output: 34)) do
      agent.ask("look around")
    end

    chat = agent.recorded_chat

    assert_predicate chat, :persisted?
    assert_equal "narration", chat.purpose
    assert_equal @playthrough, chat.playthrough
    assert_equal %w[system user assistant], chat.messages.reorder(:id).pluck(:role)
    assert_equal "You narrate.", chat.messages.find_by(role: "system").content
    assert_equal "look around", chat.messages.find_by(role: "user").content
    assert_equal "A road, and then the sea.", chat.messages.find_by(role: "assistant").content
  end

  # THE HALF THE DEBUG VIEW WAS WAITING FOR. Both live on `RubyLLM::Message`
  # already and both have columns; nothing was writing them.
  test "the answer carries its token counts and the model that wrote it" do
    agent = BaseAgent.new(purpose: "classifier", playthrough: @playthrough, model_options: OPTIONS)

    OfflineExchange.with(OfflineExchange.reply({ "intent" => "move" }, input: 118, output: 9)) do
      agent.ask("go north")
    end

    answer = agent.recorded_chat.messages.find_by(role: "assistant")

    assert_equal 118, answer.input_tokens
    assert_equal 9, answer.output_tokens
    assert_equal "gemma3:12b", answer.answering_model_id
    assert_equal 118, agent.recorded_chat.input_tokens
    assert_equal 9, agent.recorded_chat.output_tokens
  end

  # A schema'd answer is a Hash, and RubyLLM stores it in `content_raw` with
  # `content` left nil. Without that column every schema'd call in the app --
  # which is all but two -- persisted an empty assistant message.
  test "a structured answer is kept whole, not dropped" do
    agent = BaseAgent.new(purpose: "arrival", playthrough: @playthrough, model_options: OPTIONS)

    OfflineExchange.with(OfflineExchange.reply({ "description" => "Rain.", "summary" => "It rains." })) do
      agent.ask("narrate arriving")
    end

    answer = agent.recorded_chat.messages.find_by(role: "assistant")

    assert_equal({ "description" => "Rain.", "summary" => "It rains." }, answer.content_raw)
    assert_match "description", answer.text
    assert_match "Rain.", answer.text
  end

  test "an agent that is never asked anything leaves no conversation behind" do
    assert_no_difference -> { Chat.count } do
      BaseAgent.new("instructions", purpose: "location", model_options: OPTIONS).with_schema(Object.new)
    end
  end

  # --- the turn it belongs to -----------------------------------------------

  test "attribute_to! stamps this agent's messages with the turn" do
    agent = BaseAgent.new("You narrate.", purpose: "narration",
                          playthrough: @playthrough, model_options: OPTIONS)
    scene = create(:scene, story: @playthrough.story, location: @playthrough.current_location)

    OfflineExchange.with(OfflineExchange.reply("Prose.")) { agent.ask("look") }
    agent.attribute_to!(scene)

    assert_equal 2, scene.messages.count, "the prompt and the answer both belong to the turn"
    assert_nil agent.recorded_chat.messages.find_by(role: "system").scene_id,
               "the instructions are the conversation's, not any one turn's"
  end

  # The scene is recorded on the MESSAGE and not on the chat exactly so this
  # works: a durable conversation contributes two messages to each turn.
  test "a conversation spanning two turns splits its cost between them" do
    character = create(:character, story: @playthrough.story)
    first = create(:scene, story: @playthrough.story, location: @playthrough.current_location)
    second = create(:scene, story: @playthrough.story, location: @playthrough.current_location,
                            previous_scene: first)

    chat = Chat.conversation_with(character, @playthrough)

    [ first, second ].each do |scene|
      agent = BaseAgent.new(purpose: Chat::CHARACTER, playthrough: @playthrough,
                            character: character, chat: chat, model_options: OPTIONS)
      OfflineExchange.with(OfflineExchange.reply({ "action" => "She nods." }, input: 300, output: 25)) do
        agent.ask("hello")
      end
      agent.attribute_to!(scene)
    end

    assert_equal 25, first.messages.sum(:output_tokens)
    assert_equal 25, second.messages.sum(:output_tokens)
    assert_equal 1, @playthrough.chats.durable.count, "one conversation, two turns"
  end

  # --- it survives a restart ------------------------------------------------

  # THE THING QUITTING USED TO LOSE. Nothing here is held in memory between the
  # two halves: the second agent is built from a `Chat` looked up out of the
  # database, exactly as a fresh process would.
  test "a character conversation is picked up again from the database" do
    character = create(:character, story: @playthrough.story, fullname: "Maren Aske")

    first = InteractionAgent.new(character, playthrough: @playthrough)
    OfflineExchange.with(OfflineExchange.reply(reaction("She looks up.")), OfflineExchange.reply("Maren looks up.")) do
      first.ask("hello")
    end

    # A RESTART: nothing from above is reachable any more.
    reloaded_playthrough = Playthrough.find(@playthrough.id)
    reloaded_character = Character.find(character.id)

    resumed = InteractionAgent.new(reloaded_character, playthrough: reloaded_playthrough)
    OfflineExchange.with(OfflineExchange.reply(reaction("She answers.")), OfflineExchange.reply("Maren answers.")) do
      resumed.ask("what did I just say?")
    end

    assert_equal first.character_agent.recorded_chat.id, resumed.character_agent.recorded_chat.id,
                 "the same conversation, not a new one"

    said = resumed.character_agent.recorded_chat.exchange_messages.pluck(:role, :content)

    assert_equal %w[user assistant user assistant], said.map(&:first)
    assert_includes said.first.last, "hello", "the first turn is still in the conversation after the restart"
  end

  test "two playthroughs of one story do not share a character's memory" do
    character = create(:character, story: @playthrough.story)
    other = create(:playthrough, story: @playthrough.story,
                                 current_location: @playthrough.current_location)

    mine = Chat.conversation_with(character, @playthrough)
    mine.update!(model: create(:model, :ollama))
    theirs = Chat.conversation_with(character, other)

    assert_not_equal mine.id, theirs.id
    assert_not_predicate theirs, :persisted?
  end

  private

  def reaction(action)
    Interaction::Schema.required_properties.to_h { |field| [ field.to_s, "#{field}: #{action}" ] }
  end
end
