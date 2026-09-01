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

  # RubyLLM 1.15 renormalised token accounting: `input_tokens` no longer folds
  # in prompt cache reads and writes, which are exposed separately. Nothing in
  # this app reads token counts, and there are no columns backing the cache
  # figures, so they read nil -- pinned so that stays a deliberate gap rather
  # than an accident.
  test "exposes the split token accounting, with no columns behind the cache figures" do
    message = create(:message, :assistant)

    assert_equal 42, message.input_tokens
    assert_equal 17, message.output_tokens
    assert_nil message.cache_read_tokens
    assert_nil message.cache_write_tokens
    assert_not_includes Message.column_names, "cached_tokens"
    assert_not_includes Message.column_names, "cache_creation_tokens"
  end

  # Cost is derived from the registry row's pricing, so it needs a model
  # association -- another thing the acts_as migration made possible.
  test "costs the exchange from the registry's pricing" do
    message = create(:message, :assistant)

    assert_operator message.cost.total, :>, 0
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

  # --- the turn it was exchanged on -----------------------------------------

  test "belongs to the turn it was exchanged on, and survives that turn going" do
    scene = create(:scene)
    message = create(:message, scene: scene)

    assert_equal scene, message.scene
    scene.destroy

    assert_nil message.reload.scene_id, "a message belongs to its conversation first"
  end

  # --- a structured answer --------------------------------------------------

  # RubyLLM stores a schema'd answer in `content_raw` with `content` left nil.
  # Without the column every schema'd call in this app -- which is all but two --
  # persisted an empty assistant message.
  test "text reads a structured answer out of content_raw" do
    message = create(:message, :assistant, content: nil, content_raw: { "intent" => "move" })

    assert_match(/"intent"/, message.text)
    assert_match(/move/, message.text)
  end

  test "text prefers the prose when there is prose" do
    assert_equal "A road, and then the sea.", create(:message, :assistant).text
  end

  # THE BUG THIS EXISTS FOR. Replaying a stored structured answer is what every
  # resumed conversation does -- the second thing said to a character, and the
  # second of `Location::Generator`'s two calls -- and ollama refuses the whole
  # request when the content arrives as a map rather than a string.
  test "a structured answer replays as the JSON string the model wrote" do
    message = create(:message, :assistant, content: nil, content_raw: { "intent" => "move" })

    assert_equal '{"intent":"move"}', message.to_llm.content
  end

  test "a message with no structured answer replays exactly as written" do
    assert_equal "A road, and then the sea.", create(:message, :assistant).to_llm.content
  end

  # WHY THE ENCODING HAS TO BE OURS. OpenAI's formatter JSON-encodes a raw
  # payload; ollama's hands the Hash straight to the wire, and ollama answers
  # `invalid message content type: map[string]interface {}`. If this ever fails,
  # the gem has fixed it and `Message#extract_content` can go.
  test "the ollama formatter still passes a raw payload through unencoded" do
    raw = RubyLLM::Content::Raw.new({ "intent" => "move" })

    assert_kind_of Hash, RubyLLM::Providers::Ollama::Media.format_content(raw)
    assert_kind_of String, RubyLLM::Providers::OpenAI::Media.format_content(raw)
  end
end
