require "test_helper"
require "turbo/broadcastable/test_helper"

# WHAT A JOB THAT PLAYS MORE THAN ONE LINE HAS TO GET RIGHT.
#
# `Playthrough::Turn#play` drains the submissions accepted before its own so
# the accepted order survives a non-FIFO lock. That made one `Turn` play two
# turns and one delivery arrive after a newer one had landed, and both are
# states nothing in the loop had ever been in.
class Playthrough::DrainedTurnTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  NOT_A_MOVE = { "intent" => "other", "target" => "nothing", "also_named" => "nothing" }.freeze

  setup do
    story = create(:story)
    @game = create(:playthrough, story: story,
                                 character: create(:character, :protagonist, story: story, level: 10),
                                 current_location: create(:location, story: story))
    @game.update!(current_scene: create(:scene, story: story, location: @game.current_location))
  end

  # THE CLASSIFIER'S PROMPT IS ONE-SHOT, and a drained job used to hand the
  # second line the first line's conversation: same `Chat` row, with the
  # previous command and its answer replayed in front of a prompt that is
  # supposed to describe one moment.
  test "each drained line classifies against its own conversation" do
    Playthrough::Command.accept!(@game, "look around", "first")

    OfflineExchange.with(NOT_A_MOVE, "You look around the room.", NOT_A_MOVE, "The room is quiet.") do
      Playthrough::Turn.new(@game).play("wait quietly", request_token: "second")
    end

    assert_equal %w[completed completed], @game.commands.order(:id).pluck(:status)
    conversations = @game.chats.where(purpose: "classifier").order(:id).to_a
    assert_equal 2, conversations.length, "one line, one classifier conversation"
    conversations.each do |chat|
      assert_equal %w[user assistant], chat.exchange_messages.pluck(:role),
                   "a one-shot prompt carries no earlier exchange"
    end
    assert_equal [ "look around", "wait quietly" ],
                 @game.scene_chain.drop(1).map(&:typed)
  end

  # THE SAME DEFECT, WHERE IT STOPPED BEING SILENT. With a retention cap the
  # first line prunes the one-shot conversations, so the second line wrote a
  # message against a `Chat` row that was gone and the turn died on a foreign
  # key -- reported as a failed submission the player can never retry.
  test "a drained line survives the retention cap the line before it applied" do
    Playthrough::Command.accept!(@game, "look around", "first")

    with_keep_turns(0) do
      OfflineExchange.with(NOT_A_MOVE, "You look around the room.", NOT_A_MOVE, "The room is quiet.") do
        Playthrough::Turn.new(@game).play("wait quietly", request_token: "second")
      end
    end

    assert_equal %w[completed completed], @game.commands.order(:id).pluck(:status)
    assert_equal "The room is quiet.", @game.reload.current_scene.description
  end

  # AN OVERTAKEN DELIVERY SAYS NOTHING. The drain finishes the later line
  # first, so the earlier line's own job arrives after it: replaying its stored
  # refusal as a page put a refusal box for a line typed in the room before
  # this one over the room the player is standing in, and took whatever they
  # had typed since with it.
  test "an overtaken job broadcasts nothing over the turn that passed it" do
    lying_here(@game, @game.current_location, name: "red coin")
    Playthrough::Command.accept!(@game, "drop red coin", "first")
    reading = { "intent" => "drop", "target" => "red coin", "also_named" => "nothing" }

    drained = capture_turbo_stream_broadcasts(@game) do
      BaseAgent.stub(:new, FakeAgent.new(reading, "You pick up the red coin.")) do
        NarrationJob.perform_now(@game.id, "/take red coin", "second")
      end
    end

    assert_equal %w[completed completed], @game.commands.order(:id).pluck(:status)
    assert_includes @game.reload.carried.map(&:name), "red coin"
    assert_includes drained.last.to_html, "what do you do?"
    assert_not_includes drained.last.to_html, "drop red coin",
                        "the later line's page is the one that stands"

    overtaken = capture_turbo_stream_broadcasts(@game) do
      BaseAgent.stub(:new, ->(*) { flunk "an overtaken delivery must not ask a model" }) do
        NarrationJob.perform_now(@game.id, "drop red coin", "first")
      end
    end

    assert_empty overtaken, "the page the player is reading is newer than this submission"
    assert_includes @game.reload.carried.map(&:name), "red coin", "and nothing was undone"
  end

  # THE OTHER HALF OF THE SAME RULE, and the reason the suppression is keyed on
  # being overtaken rather than on being a replay: the newest submission is
  # what the player is looking at, so its own duplicate delivery still refreshes
  # the page -- refusal, crisis notice and all.
  test "a duplicate delivery of the newest submission still refreshes its page" do
    Playthrough::Command.accept!(@game, "look around", "first")
    refusal = { "intent" => "take", "target" => "a brass key nobody has", "also_named" => "nothing" }

    capture_turbo_stream_broadcasts(@game) do
      BaseAgent.stub(:new, FakeAgent.new(refusal)) do
        NarrationJob.perform_now(@game.id, "look around", "first")
      end
    end

    repeated = capture_turbo_stream_broadcasts(@game) do
      BaseAgent.stub(:new, ->(*) { flunk "a duplicate delivery must not ask a model" }) do
        NarrationJob.perform_now(@game.id, "look around", "first")
      end
    end

    assert_equal 1, repeated.length
    assert_includes repeated.sole.to_html, "look around", "its own refusal is still what the page says"
  end

  private

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
