require "test_helper"

class ToolCallTest < ActiveSupport::TestCase
  test "the factory builds a valid tool call" do
    assert_predicate build(:tool_call), :valid?
  end

  test "requires a message" do
    tool_call = build(:tool_call, message: nil)

    assert_not_predicate tool_call, :valid?
    assert_includes tool_call.errors.attribute_names, :message
  end

  test "belongs to the message that issued it" do
    message = create(:message, :assistant)

    assert_equal message, create(:tool_call, message: message).message
  end

  # Arguments round trip through a JSON column, so keys come back as strings.
  test "stores arguments as JSON" do
    tool_call = create(:tool_call, arguments: { "scene_id" => 7, "verbose" => true })

    assert_equal({ "scene_id" => 7, "verbose" => true }, tool_call.reload.arguments)
  end

  test "defaults arguments to an empty hash" do
    tool_call = ToolCall.create!(message: create(:message, :assistant), tool_call_id: "call_x", name: "noop")

    assert_equal({}, tool_call.arguments)
  end

  test "has one result message" do
    tool_call = create(:tool_call)
    result = create(:message, parent_tool_call: tool_call)

    assert_equal result, tool_call.result
  end

  test "destroying a tool call nullifies its result rather than deleting it" do
    tool_call = create(:tool_call)
    result = create(:message, parent_tool_call: tool_call)

    assert_no_difference -> { Message.count } do
      tool_call.destroy
    end
    assert_nil result.reload.parent_tool_call
  end

  test "keeps the provider's own call id distinct from the primary key" do
    tool_call = create(:tool_call, tool_call_id: "call_abc123")

    assert_equal "call_abc123", tool_call.tool_call_id
    assert_not_equal tool_call.id.to_s, tool_call.tool_call_id
  end
end
