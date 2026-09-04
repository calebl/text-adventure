require "test_helper"

# THE ONE CALL THAT WRITES WHAT A READABLE THING SAYS, and the guarantees around
# it: only for a thing the world marked readable, only when nobody has written
# the words yet, and only once.
#
# `Item::Registry` is the ordinary writer -- a thing realized with a room is born
# with its words. This exists for the gap: a seeded note whose file did not spell
# them out, and a row older than the columns.
class Item::InscriberTest < ActiveSupport::TestCase
  WORDS = "Midnight. The Bell. They know about the maps.".freeze

  def setup
    @story = create(:story)
    @room = create(:location, story: @story, name: "The Boarding House Hallway")
  end

  def inscribe(item, *answers)
    agent = FakeAgent.new(*answers)
    inscriber = Item::Inscriber.new(item)
    result = BaseAgent.stub(:new, agent) { inscriber.inscribe! }
    [ result, agent, inscriber ]
  end

  # THE GATE, and it is the whole gate. Nothing generates text for a thing
  # nobody marked readable -- not once, not ever.
  test "asks nothing at all for a thing with no writing on it" do
    item = create(:item, :lying, location: @room)

    words, agent, inscriber = inscribe(item, { "inscription" => WORDS })

    assert_nil words
    assert_empty agent.prompts
    assert_not inscriber.asked?
    assert_nil item.reload.inscription
  end

  test "writes the words once for a readable thing that has none" do
    item = create(:item, :lying, :unwritten, location: @room, name: "folded note")

    words, agent, inscriber = inscribe(item, { "inscription" => WORDS })

    assert_equal WORDS, words
    assert_equal WORDS, item.reload.inscription
    assert_equal 1, agent.prompts.size
    assert inscriber.asked?
  end

  # THE WHOLE POINT. A second reading is a database read: the words came out of
  # the records the first time, so they are the same string the second time and
  # not another guess at them.
  test "never asks again once the words are on record" do
    item = create(:item, :lying, :readable, location: @room)

    words, agent, inscriber = inscribe(item)

    assert_equal item.inscription, words
    assert_empty agent.prompts
    assert_not inscriber.asked?
  end

  test "sanitizes what came back" do
    item = create(:item, :lying, :unwritten, location: @room, name: "folded note")

    words, = inscribe(item, { "inscription" => "  Midnight. 🔔 The Bell.  " })

    assert_equal "Midnight.  The Bell.".squeeze(" "), words.squeeze(" ")
  end

  # There is no second chance at this field: it is written once and then quoted
  # to the player verbatim on every later reading, so half a sentence would be
  # half a sentence forever. The check runs inside `BaseAgent#ask`'s attempt
  # loop, which is what makes it a rotation rather than a dead turn.
  test "an answer arriving at its cap fails the call rather than being stored" do
    item = create(:item, :lying, :unwritten, location: @room, name: "folded note")

    assert_raises(SanitizesGeneratedText::TruncatedTextError) do
      inscribe(item, { "inscription" => "x" * Item::INSCRIPTION_LIMIT })
    end

    assert_nil item.reload.inscription
  end

  test "an empty answer is a failed call and nothing is stored" do
    item = create(:item, :lying, :unwritten, location: @room, name: "folded note")

    assert_raises(BaseAgent::SchemaIgnoredError) { inscribe(item, { "inscription" => "   " }) }
    assert_nil item.reload.inscription
  end

  # The prompt is the world, the thing and where it is -- what somebody writing
  # the note would have known -- and it asks for the text rather than for a
  # description of the object.
  test "the prompt carries the thing and the room it is in" do
    item = create(:item, :lying, :unwritten, location: @room, name: "folded note",
                  description: "A square of ward paper folded twice.")

    _, agent, = inscribe(item, { "inscription" => WORDS })
    prompt = agent.prompts.sole

    assert_includes prompt, "folded note"
    assert_includes prompt, "A square of ward paper folded twice."
    assert_includes prompt, "The Boarding House Hallway"
    assert_includes prompt, @story.title
  end

  # A thing in somebody's hands is answered for by the room they are standing
  # in, which is what `Item#whereabouts` already says.
  test "a thing somebody is holding is described by whose hands it is in" do
    holder = create(:character, story: @story, fullname: "Odile Vance")
    item = create(:item, :unwritten, character: holder, name: "folded note")

    _, agent, = inscribe(item, { "inscription" => WORDS })

    assert_includes agent.prompts.sole, "held by Odile Vance"
  end
end
