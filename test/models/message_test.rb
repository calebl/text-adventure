require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "the factory builds a valid message" do
    assert_predicate build(:message), :valid?
  end

  test "requires a chat" do
    message = build(:message, chat: nil)

    assert_not_predicate message, :valid?
    assert_includes message.errors.attribute_names, :chat
  end

  test "belongs to a chat" do
    chat = create(:chat)

    assert_equal chat, create(:message, chat: chat).chat
  end

  test "stores the role and content it was given" do
    message = create(:message, :assistant)

    assert_equal "assistant", message.role
    assert_equal "A road, and then the sea.", message.content
  end

  # Token counts are persisted per message. Nothing in the app reads them
  # today, but they are the columns a token-accounting change would land on.
  test "persists token counts" do
    message = create(:message, :assistant)

    assert_equal 42, message.reload.input_tokens
    assert_equal 17, message.output_tokens
  end

  test "has many tool calls" do
    message = create(:message, :assistant)
    tool_call = create(:tool_call, message: message)

    assert_equal [ tool_call ], message.tool_calls.to_a
  end

  test "destroying a message destroys its tool calls" do
    message = create(:message, :assistant)
    create(:tool_call, message: message)

    assert_difference -> { ToolCall.count }, -1 do
      message.destroy
    end
  end

  # A tool result is a message that points back at the call that produced it.
  test "links back to the tool call it answers" do
    tool_call = create(:tool_call)
    result = create(:message, parent_tool_call: tool_call)

    assert_equal tool_call, result.parent_tool_call
    assert_equal result, tool_call.reload.result
  end

  test "parent tool call is optional" do
    assert_nil create(:message).parent_tool_call
  end

  test "exposes the RubyLLM tool predicates" do
    message = create(:message)

    assert_respond_to message, :to_llm
    assert_respond_to message, :tool_call?
    assert_respond_to message, :tool_result?
  end

  test "an ordinary message is neither a tool call nor a tool result" do
    message = create(:message)

    assert_not message.tool_call?
    assert_not message.tool_result?
  end

  test "a message carrying tool calls reports itself as a tool call" do
    message = create(:message, :assistant)
    create(:tool_call, message: message)

    assert_predicate message.reload, :tool_call?
  end

  test "a message answering a tool call reports itself as a tool result" do
    result = create(:message, parent_tool_call: create(:tool_call))

    assert_predicate result, :tool_result?
  end
end
