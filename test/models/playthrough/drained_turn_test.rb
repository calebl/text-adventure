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

  # A PAGE THE CONSUMER CANNOT DELIVER IS NOT A LINE THE PLAYER LOSES. The
  # pending page is broadcast from INSIDE `Command#execute!`, so a cable write
  # that raised marked a submission `failed` before its line had ever been
  # played: the player read an internal-failure notice for a line that was
  # simply gone, and a redelivery of that token raised instead of replaying it.
  test "a pending page that cannot be broadcast still plays every accepted line" do
    Playthrough::Command.accept!(@game, "look around", "first")
    attempted = []
    broadcast = Turbo::StreamsChannel.method(:broadcast_replace_to)
    refusing_start = lambda do |*args, **kwargs|
      line = kwargs.dig(:locals, :command)
      attempted << line if line
      raise ActiveRecord::StatementInvalid, "SQLITE_BUSY: solid_cable_messages" if line

      broadcast.call(*args, **kwargs)
    end

    Turbo::StreamsChannel.stub(:broadcast_replace_to, refusing_start) do
      OfflineExchange.with(NOT_A_MOVE, "You look around the room.", NOT_A_MOVE, "The room is quiet.") do
        NarrationJob.perform_now(@game.id, "wait quietly", "second")
      end
    end

    assert_equal [ "look around", "wait quietly" ], attempted, "both pending pages were attempted"
    assert_equal %w[completed completed], @game.commands.order(:id).pluck(:status)
    assert_equal [ "look around", "wait quietly" ], @game.reload.scene_chain.drop(1).map(&:typed)
    assert_equal "The room is quiet.", @game.current_scene.description

    replayed = capture_turbo_stream_broadcasts(@game) do
      BaseAgent.stub(:new, ->(*) { flunk "a redelivery must not ask a model" }) do
        NarrationJob.perform_now(@game.id, "look around", "first")
      end
    end

    assert_empty replayed, "the drain passed that submission, so its own delivery still says nothing"
    assert_equal %w[completed completed], @game.commands.order(:id).pluck(:status)
  end

  # THE SAME RULE ONE ROW ALONG. The final page is delivered outside the
  # receipt, so a failure there cost no submission its status -- it raised out
  # of the drain loop instead, and every line accepted behind the one that had
  # just finished stayed pending with nothing left to play it.
  test "a finish page that cannot be broadcast does not strand the line behind it" do
    Playthrough::Command.accept!(@game, "look around", "first")
    finishes = 0
    broadcast = Turbo::StreamsChannel.method(:broadcast_replace_to)
    refusing_first_finish = lambda do |*args, **kwargs|
      if kwargs.dig(:locals, :command).nil?
        finishes += 1
        raise ActiveRecord::StatementInvalid, "SQLITE_BUSY: solid_cable_messages" if finishes == 1
      end

      broadcast.call(*args, **kwargs)
    end

    Turbo::StreamsChannel.stub(:broadcast_replace_to, refusing_first_finish) do
      OfflineExchange.with(NOT_A_MOVE, "You look around the room.", NOT_A_MOVE, "The room is quiet.") do
        NarrationJob.perform_now(@game.id, "wait quietly", "second")
      end
    end

    assert_equal 2, finishes, "the line behind the undelivered page reached its own page"
    assert_equal %w[completed completed], @game.commands.order(:id).pluck(:status)
    assert_equal "The room is quiet.", @game.reload.current_scene.description
  end

  # AN OBSERVER THAT FAILS IS NOT THE TURN THAT FAILED, which is the other half
  # of the rule: only delivery is swallowed, so the engine's own error still
  # reaches the caller and the submission still records what really happened.
  test "a failure notice that cannot be delivered still raises the engine's own error" do
    failed = assert_raises(RuntimeError) do
      BaseAgent.stub(:new, FakeAgent.new(RuntimeError.new("provider unavailable"))) do
        Playthrough::Turn.new(@game).play("wait quietly", request_token: "only",
                                          on_error: ->(_) { raise IOError, "the cable is down" })
      end
    end

    assert_equal "provider unavailable", failed.message
    assert_equal [ "failed" ], @game.commands.pluck(:status)
    assert_equal [ "error" ], @game.commands.pluck(:error_kind)
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
