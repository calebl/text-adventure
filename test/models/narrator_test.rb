require "test_helper"

# Narrator is the top-level storyteller: a RubyLLM chat seeded with the system
# directive and an opening line. It makes no schema-constrained calls, so the
# thing worth pinning is the conversation it sets up before anyone asks it
# anything -- and that it never speaks for the player.
class NarratorTest < ActiveSupport::TestCase
  test "opens a chat on the default model" do
    chat = FakeChat.new
    captured = nil

    RubyLLM.stub(:chat, ->(**options) { captured = options; chat }) do
      Narrator.new
    end

    assert_equal Narrator::DEFAULT_MODEL, captured[:model]
  end

  test "accepts a model override" do
    captured = nil

    RubyLLM.stub(:chat, ->(**options) { captured = options; FakeChat.new }) do
      Narrator.new(model: "mistralai/mistral-medium-3.1")
    end

    assert_equal "mistralai/mistral-medium-3.1", captured[:model]
  end

  test "installs the system directive as instructions" do
    narrator = build_narrator

    assert_equal Narrator::SYSTEM_DIRECTIVE, narrator.chat.instructions
  end

  test "seeds the transcript with an opening assistant message" do
    narrator = build_narrator

    assert_equal 1, narrator.chat.added_messages.count
    assert_equal :assistant, narrator.chat.added_messages.first[:role]
    assert_match(/narrator for your adventure/, narrator.chat.added_messages.first[:content])
  end

  test "exposes the underlying chat" do
    chat = FakeChat.new

    RubyLLM.stub(:chat, ->(**) { chat }) do
      assert_same chat, Narrator.new.chat
    end
  end

  test "add_user_message forwards the prompt and returns the reply text" do
    narrator = build_narrator("You push open the door.")

    assert_equal "You push open the door.", narrator.add_user_message("open the door")
    assert_equal [ "open the door" ], narrator.chat.prompts
  end

  test "last_assistant_message is the opening line before anything is asked" do
    narrator = build_narrator

    assert_match(/What kind of story would you like to begin\?/, narrator.last_assistant_message)
  end

  test "last_assistant_message follows the conversation" do
    narrator = build_narrator("A road, and then the sea.", "The sea is grey today.")

    narrator.add_user_message("look around")
    assert_equal "A road, and then the sea.", narrator.last_assistant_message

    narrator.add_user_message("look at the sea")
    assert_equal "The sea is grey today.", narrator.last_assistant_message
  end

  test "transcript prints one line per message" do
    narrator = build_narrator("A road,\nand then the sea.")
    narrator.add_user_message("look around")

    output = capture_io { narrator.transcript }.first

    assert_match(/^\[ASSISTANT\] Hello!/, output)
    assert_match(/^\[USER\] look around$/, output)
    assert_match(/^\[ASSISTANT\] A road,$/, output)
  end

  # These are the load-bearing sentences of the directive. The whole point of
  # the narrator is that the player keeps agency; if these are edited away the
  # narrator starts playing the game for them.
  test "the directive forbids acting on the player's behalf" do
    assert_match(/DO NOT TAKE ACTIONS FOR THE USER/, Narrator::SYSTEM_DIRECTIVE)
    assert_match(/Do not automatically move the \[user\]/, Narrator::SYSTEM_DIRECTIVE)
  end

  test "the directive requires second person narration" do
    assert_match(/second person/, Narrator::SYSTEM_DIRECTIVE)
  end

  test "the directive requires onward exits at the end of every scene" do
    assert_match(/list of places that the \[user\] can explore further/, Narrator::SYSTEM_DIRECTIVE)
  end

  test "the directive names the tools it expects to be given" do
    assert_match(/get_scene_details/, Narrator::SYSTEM_DIRECTIVE)
    assert_match(/get_universe_rules/, Narrator::SYSTEM_DIRECTIVE)
  end

  private

  def build_narrator(*responses)
    chat = FakeChat.new(*responses)
    RubyLLM.stub(:chat, ->(**) { chat }) { Narrator.new }
  end
end
