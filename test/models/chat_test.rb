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

  # `model_id` is the string RubyLLM resolves when the record is turned back
  # into a live chat, so it has to survive a round trip untouched.
  test "remembers the model it was created with" do
    chat = create(:chat, model_id: "mistralai/mistral-medium-3.1")

    assert_equal "mistralai/mistral-medium-3.1", chat.reload.model_id
  end

  test "exposes the RubyLLM chat conversion and message helpers" do
    chat = create(:chat)

    assert_respond_to chat, :to_llm
    assert_respond_to chat, :add_message
    assert_respond_to chat, :with_instructions
    assert_respond_to chat, :with_schema
    assert_respond_to chat, :with_tool
  end
end
