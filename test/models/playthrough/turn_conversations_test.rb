require "test_helper"

# THE LOOP, WITH THE MODEL CALLS ACTUALLY RECORDED.
#
# `turn_test.rb` stands a `FakeAgent` in at `BaseAgent.new`, which is right for
# testing what the loop does with an answer but writes no rows. This runs the
# real `BaseAgent` and replaces only the HTTP call (`OfflineExchange`), so what
# is under test is the persistence itself: the chats a turn writes, the tokens
# on them, and what is left after the server has been restarted.
class Playthrough::TurnConversationsTest < ActiveSupport::TestCase
  CLASSIFY_TALK = { "intent" => "talk", "target" => "Grenn Ollivar" }.freeze
  CLASSIFY_OTHER = { "intent" => "other", "target" => "nothing" }.freeze

  setup do
    @story = create(:story)
    @protagonist = create(:character, story: @story, fullname: "Iri Calder", is_protagonist: true)
    @here = create(:location, story: @story, name: "Ashgate Market")
    @grenn = create(:character, story: @story, fullname: "Grenn Ollivar", nickname: "Old Grenn")
    @playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
    # Grenn has to be standing here for the talk branch to be reachable at all:
    # the cast comes from the last scene in this location that recorded anybody.
    create(:scene, story: @story, location: @here, characters: [ @protagonist, @grenn ])
  end

  # --- a turn's conversation is persisted ------------------------------------

  test "a narrated turn keeps both of its conversations, filed under the turn" do
    scene = play("look at the awnings", CLASSIFY_OTHER, OfflineExchange.reply("Canvas, wet through.", input: 90, output: 12))

    purposes = scene.messages.map { |message| message.chat.purpose }.uniq.sort

    assert_equal %w[classifier narration], purposes
    assert_equal 4, scene.messages.count, "a prompt and an answer for each"
    assert_equal @playthrough, scene.messages.first.chat.playthrough
  end

  test "a talking turn keeps the classifier, the character and the narration" do
    scene = play("ask Grenn about the charts", CLASSIFY_TALK, reaction, OfflineExchange.reply("Grenn sets the crate down."))

    purposes = scene.messages.map { |message| message.chat.purpose }.uniq.sort

    assert_equal [ "character", "classifier", "interaction-narration" ], purposes
  end

  # THE CONSUMER THAT WAS WAITING. Both numbers live on `RubyLLM::Message` and
  # both have columns; until now nothing wrote either.
  test "the turn's cost and the model that answered are both recorded" do
    scene = play("look at the awnings", CLASSIFY_OTHER, OfflineExchange.reply("Canvas.", input: 90, output: 12))

    assert_equal 210, scene.messages.sum(:input_tokens), "120 to classify, 90 to narrate"
    assert_equal 52, scene.messages.sum(:output_tokens)
    assert_equal [ "gemma3:12b" ], scene.messages.filter_map { |message| message.model&.model_id }.uniq
  end

  # The command is in the classifier's prompt, which runs on every turn -- so a
  # turn that was not a conversation is no longer silent about what produced it.
  test "what the player typed is recoverable from the classifier's own prompt" do
    scene = play("look at the awnings", CLASSIFY_OTHER, OfflineExchange.reply("Canvas."))

    classifier = scene.messages.find { |message| message.chat.purpose == "classifier" && message.role == "user" }

    assert_includes classifier.content, "look at the awnings"
  end

  # --- and it reaches the debug view ----------------------------------------

  test "the debug view shows the cost and the model for the turn just taken" do
    play("look at the awnings", CLASSIFY_OTHER, OfflineExchange.reply("Canvas.", input: 90, output: 12))

    turn = Playthrough::Debug.new(Playthrough.find(@playthrough.id)).latest_turn

    assert_predicate turn, :recorded?
    assert_equal 210, turn.input_tokens
    assert_equal 52, turn.output_tokens
    assert_equal [ "gemma3:12b" ], turn.models
    assert_equal %w[classifier narration], turn.conversations.map(&:purpose).sort
    assert_equal "look at the awnings", turn.typed
  end

  test "the debug view finds the conversation a character is still having" do
    play("ask Grenn about the charts", CLASSIFY_TALK, reaction, OfflineExchange.reply("Grenn nods."))

    debug = Playthrough::Debug.new(Playthrough.find(@playthrough.id))

    assert_equal [ @grenn ], debug.durable_conversations.map(&:character)
    assert_operator debug.output_tokens, :>, 0
  end

  # --- history survives a restart -------------------------------------------

  # Two turns, with everything from the first dropped in between. The second
  # `Playthrough::Turn` is built on a record read back out of the database, so
  # what it picks up is what a fresh process would.
  test "a character remembers the previous turn across a restart" do
    play("ask Grenn about the charts", CLASSIFY_TALK, reaction("She sets the crate down."), OfflineExchange.reply("Grenn sets it down."))

    @playthrough = Playthrough.find(@playthrough.id)
    play("and the tunnel?", CLASSIFY_TALK, reaction("She goes still."), OfflineExchange.reply("Grenn goes still."))

    conversation = @playthrough.chats.durable.sole

    assert_equal 1, @playthrough.chats.durable.count, "the same conversation, picked up"
    assert_equal 4, conversation.exchange_messages.count
    assert_includes conversation.exchange_messages.first.content, "ask Grenn about the charts"
    assert_equal 2, Interaction.for_character(@grenn).count
  end

  # The ceiling is what makes replaying it safe: `character_instructions`
  # already inlines the whole universe and the local models run in 4,096 tokens.
  test "the replayed history is trimmed to the ceiling, and the interactions are not" do
    3.times do |n|
      @playthrough = Playthrough.find(@playthrough.id)
      play("question #{n}", CLASSIFY_TALK, reaction, OfflineExchange.reply("Grenn answers #{n}."))
    end

    conversation = @playthrough.chats.durable.sole

    # THE CEILING IS ON WHAT IS REPLAYED, and it is applied when the conversation
    # is picked up -- so at rest it holds the ceiling plus the exchange just
    # added, and picking it up again is what trims it back.
    assert_equal (Chat::HISTORY_EXCHANGES + 1) * 2, conversation.exchange_messages.count

    @playthrough = Playthrough.find(@playthrough.id)
    InteractionAgent.new(Character.find(@grenn.id), playthrough: @playthrough).character_agent.chat

    assert_equal Chat::HISTORY_EXCHANGES * 2, conversation.reload.exchange_messages.count
    assert_includes conversation.exchange_messages.first.content, "question 1",
                    "the oldest exchanges are the ones that go"
    assert_equal 3, Interaction.for_character(@grenn).count, "nothing is forgotten -- it is on Interaction"
  end

  # --- the audit trail is bounded -------------------------------------------

  # THE DEFAULT, AND THE WHOLE POINT OF THE CHANGE. `Chat::KEEP_TURNS` is nil
  # unless somebody sets `TA_CHAT_KEEP_TURNS`, and nil keeps everything -- so a
  # game played well past the old 25-turn ceiling still has every receipt.
  #
  # Driven through the real loop rather than by calling the pruner directly,
  # because the loop is what used to throw these away: `Playthrough::Turn#play`
  # calls `prune_conversations!` at the end of EVERY turn. This must not be able
  # to regress quietly.
  test "by default the loop prunes nothing, however long the game runs" do
    assert_nil Chat::KEEP_TURNS, "the shipped default keeps everything"
    refute_predicate Chat, :capped?

    30.times do |n|
      @playthrough = Playthrough.find(@playthrough.id)
      play("look #{n}", CLASSIFY_OTHER, OfflineExchange.reply("Prose #{n}."))
    end

    @playthrough = Playthrough.find(@playthrough.id)

    assert_equal 30, @playthrough.scene_chain.size, "well past the old ceiling of 25"
    assert_equal 60, @playthrough.chats.one_shot.count, "two conversations a turn, every turn kept"

    # The FIRST turn's receipts specifically -- the one the old default would
    # have destroyed twenty-nine turns ago.
    first = @playthrough.scene_chain.first

    assert_equal 4, first.messages.count, "a prompt and an answer for each of its two conversations"
    assert_includes first.messages.map(&:content).join, "look 0"
    assert_predicate Playthrough::Debug.new(@playthrough).turns.first, :recorded?,
                     "and the debug page can still show what it cost"
  end

  test "prune_conversations! is a no-op when no cap is set" do
    2.times do |n|
      @playthrough = Playthrough.find(@playthrough.id)
      play("look #{n}", CLASSIFY_OTHER, OfflineExchange.reply("Prose #{n}."))
    end

    playthrough = Playthrough.find(@playthrough.id)

    assert_equal 0, playthrough.prune_conversations!(keep: nil)
    assert_equal 4, playthrough.chats.one_shot.count
  end

  # THE OPT-IN CAP, which still behaves exactly as it did when it was the
  # default: set `TA_CHAT_KEEP_TURNS` and the older receipts go on every turn.
  test "the loop prunes the one-shot conversations older than the ceiling" do
    2.times do |n|
      @playthrough = Playthrough.find(@playthrough.id)
      play("look #{n}", CLASSIFY_OTHER, OfflineExchange.reply("Prose #{n}."))
    end

    assert_equal 4, @playthrough.chats.one_shot.count

    @playthrough = Playthrough.find(@playthrough.id)
    with_keep_turns(1) do
      play("look again", CLASSIFY_OTHER, OfflineExchange.reply("More prose."))
    end

    assert_equal 2, @playthrough.chats.one_shot.count, "only the newest turn's two are left"
    assert_equal 3, Playthrough.find(@playthrough.id).scene_chain.size,
                 "the turns themselves are untouched -- it is the receipts that go"
  end

  private

  # Plays one command with the loop's model calls queued in the order it makes
  # them. Nothing here reaches the network; everything else is the real thing.
  def play(command, *replies)
    OfflineExchange.with(*replies) do
      Playthrough::Turn.new(@playthrough).play(command) { |_chunk| nil }
    end
  end

  def reaction(action = "She sets down the crate.")
    OfflineExchange.reply(
      Interaction::Schema.required_properties.to_h { |field| [ field.to_s, field == :action ? action : "#{field} value" ] }
    )
  end

  def with_keep_turns(keep)
    original = Chat.const_get(:KEEP_TURNS)
    Chat.send(:remove_const, :KEEP_TURNS)
    Chat.const_set(:KEEP_TURNS, keep)
    yield
  ensure
    Chat.send(:remove_const, :KEEP_TURNS)
    Chat.const_set(:KEEP_TURNS, original)
  end
end
