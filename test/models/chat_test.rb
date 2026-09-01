require "test_helper"

# Chat/Message/ToolCall are the RubyLLM persistence trio. They carry no
# application logic of their own -- everything they do comes from the
# `acts_as_*` macros -- so these tests pin the wiring those macros install.
# That wiring is exactly what a RubyLLM upgrade is free to change underneath us.
class ChatTest < ActiveSupport::TestCase
  test "the factory builds a valid chat" do
    assert_predicate build(:chat), :valid?
  end

  test "has many messages" do
    chat = create(:chat)
    first = create(:message, chat: chat)
    second = create(:message, :assistant, chat: chat)

    assert_equal [ first, second ], chat.messages.to_a
  end

  test "orders messages oldest first regardless of insertion order" do
    chat = create(:chat)
    newer = create(:message, chat: chat, created_at: 1.minute.ago)
    older = create(:message, chat: chat, created_at: 1.hour.ago)

    assert_equal [ older, newer ], chat.messages.to_a
  end

  test "destroying a chat destroys its messages" do
    chat = create(:chat)
    create(:message, chat: chat)

    assert_difference -> { Message.count }, -1 do
      chat.destroy
    end
  end

  # CHANGED BY THE RubyLLM 1.7 acts_as MIGRATION. `chats.model_id` used to be a
  # string column holding the provider's model name. It is now a foreign key
  # into `models`, and `Chat#model_id` reads the name back through that
  # association -- so the value round trips, but through a different mechanism
  # and only if a matching registry row exists.
  test "remembers the model it was created with" do
    model = create(:model, model_id: "mistralai/mistral-medium-3.1", provider: "openrouter", name: "Mistral Medium 3.1")
    chat = create(:chat, model: model)

    assert_equal "mistralai/mistral-medium-3.1", chat.reload.model_id
    assert_equal "openrouter", chat.provider
    assert_equal model, chat.model
  end

  # Assigning `model_id` a string still works, but it is no longer a plain
  # column write: a before_save hook resolves it against the registry and
  # instantiates the provider, which needs that provider to be configured.
  test "assigning a model name resolves it against the registry on save" do
    create(:model, model_id: "minimax/minimax-m3", provider: "openrouter", name: "MiniMax M3")

    with_openrouter_key do
      chat = Chat.create!(model_id: "minimax/minimax-m3")

      assert_equal "minimax/minimax-m3", chat.model_id
      assert_equal "openrouter", chat.model.provider
    end
  end

  test "resolving a model name needs the provider configured" do
    create(:model, model_id: "minimax/minimax-m3", provider: "openrouter", name: "MiniMax M3")

    assert_raises(RubyLLM::ConfigurationError) { Chat.create!(model_id: "minimax/minimax-m3") }
  end

  # An unsaved model name still has to exist in the registry. The table is the
  # registry now, so an unknown name fails at save time rather than at ask time.
  test "an unknown model name is rejected at save time" do
    with_openrouter_key do
      assert_raises(RubyLLM::ModelNotFoundError) { Chat.create!(model_id: "vendor/does-not-exist") }
    end
  end

  test "belongs to a registry model" do
    model = create(:model)

    assert_equal model, create(:chat, model: model).model
  end

  test "exposes the RubyLLM chat conversion and message helpers" do
    chat = create(:chat)

    assert_respond_to chat, :to_llm
    assert_respond_to chat, :add_message
    assert_respond_to chat, :with_instructions
    assert_respond_to chat, :with_schema
    assert_respond_to chat, :with_tool
  end

  # --- what the game files a conversation under -----------------------------

  test "purpose is a key into a fixed table, not free text" do
    assert_predicate build(:chat, purpose: Chat::CHARACTER), :valid?
    assert_not build(:chat, purpose: "whatever-i-felt-like").valid?
    assert_predicate build(:chat, purpose: nil), :valid?, "a conversation nothing filed is still a conversation"
  end

  test "one_shot and durable are the two kinds, and they do not overlap" do
    playthrough = create(:playthrough)
    durable = create(:chat, purpose: Chat::CHARACTER, playthrough: playthrough)
    one_shot = create(:chat, purpose: "classifier", playthrough: playthrough)
    unfiled = create(:chat, playthrough: playthrough)

    assert_equal [ durable ], playthrough.chats.durable.to_a
    assert_equal [ one_shot, unfiled ].sort_by(&:id), playthrough.chats.one_shot.order(:id).to_a
  end

  # THE RESUME KEY. The same player talking to the same person continues the
  # same conversation; a different playthrough of the same world does not.
  test "conversation_with finds the chat this playthrough already has" do
    playthrough = create(:playthrough)
    character = create(:character, story: playthrough.story)
    existing = create(:chat, purpose: Chat::CHARACTER, playthrough: playthrough, character: character)

    assert_equal existing, Chat.conversation_with(character, playthrough)
    assert_not_predicate Chat.conversation_with(create(:character, story: playthrough.story), playthrough), :persisted?
    assert_not_predicate Chat.conversation_with(character, create(:playthrough)), :persisted?
  end

  test "conversation_with copes with nothing to key on" do
    chat = Chat.conversation_with(nil, nil)

    assert_equal Chat::CHARACTER, chat.purpose
    assert_not_predicate chat, :persisted?
  end

  # --- the ceiling on replay ------------------------------------------------

  # RubyLLM rebuilds every request out of every persisted message, so a chat
  # that keeps more history than it means to send WILL send it. Trimming is
  # therefore deleting, and the substance is kept on `Interaction` instead.
  test "prune_history! keeps the instructions and the last few exchanges" do
    chat = create(:chat)
    create(:message, :system, chat: chat)
    six = 6.times.map { |n| create(:message, chat: chat, role: n.even? ? "user" : "assistant", content: "m#{n}") }

    assert_equal 2, chat.prune_history!(exchanges: 2)

    kept = chat.messages.reorder(:id).pluck(:role, :content)

    assert_equal "system", kept.first.first, "a character sheet is not optional"
    assert_equal %w[m2 m3 m4 m5], kept.drop(1).map(&:last)
    assert_equal six.last, chat.messages.reorder(:id).last
  end

  test "prune_history! leaves a conversation shorter than the ceiling alone" do
    chat = create(:chat)
    create(:message, chat: chat)
    create(:message, :assistant, chat: chat)

    assert_equal 0, chat.prune_history!(exchanges: 2)
    assert_equal 2, chat.messages.count
  end

  test "prune_history! with no budget drops the whole exchange but not the instructions" do
    chat = create(:chat)
    create(:message, :system, chat: chat)
    create(:message, chat: chat)
    create(:message, :assistant, chat: chat)

    assert_equal 2, chat.prune_history!(exchanges: 0)
    assert_equal [ "system" ], chat.messages.reload.pluck(:role)
  end

  # --- what it cost, and who answered ---------------------------------------

  test "reports what the conversation cost and which model actually answered" do
    ollama = create(:model, :ollama)
    chat = create(:chat, model: ollama)
    create(:message, chat: chat, input_tokens: 100, output_tokens: 0)
    create(:message, :assistant, chat: chat, model: ollama, input_tokens: 0, output_tokens: 25)

    assert_equal 100, chat.input_tokens
    assert_equal 25, chat.output_tokens
    assert_equal [ "gemma3:12b" ], chat.answering_model_ids
  end

  private

  # Model resolution instantiates the provider, which refuses to build without
  # its key. Nothing here reaches the network -- the registry row is local.
  def with_openrouter_key
    original = RubyLLM.config.openrouter_api_key
    RubyLLM.config.openrouter_api_key = "sk-test-not-a-real-key"
    yield
  ensure
    RubyLLM.config.openrouter_api_key = original
  end
end
