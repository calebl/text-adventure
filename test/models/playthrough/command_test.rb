require "test_helper"

class Playthrough::CommandTest < ActiveSupport::TestCase
  test "the deterministic factory builds a valid submission" do
    assert_predicate build(:playthrough_command), :valid?
  end

  test "a token and its line identify one submission within one playthrough" do
    first = create(:playthrough_command)
    assert_equal first, Playthrough::Command.accept!(first.playthrough, first.command, first.request_token)

    # A SECOND LINE ON ONE TOKEN IS A SECOND SUBMISSION, not a collision: the
    # form is only re-rendered between turns, so this is what a player typing
    # while the previous turn runs looks like from here.
    assert_difference -> { Playthrough::Command.count } do
      second = Playthrough::Command.accept!(first.playthrough, "/wait", first.request_token)
      assert_not_equal first, second
      assert_equal "/wait", second.command
    end

    other = create(:playthrough)
    assert_difference -> { Playthrough::Command.count } do
      Playthrough::Command.accept!(other, first.command, first.request_token)
    end
  end

  test "a completed refusal is returned without reading the command again" do
    submission = create(:playthrough_command)
    refusal = Playthrough::Refusal.new(kind: :unresolved, typed: "take clouds", fact: "Nothing matches.")
    submission.execute! { refusal }

    repeated = submission.reload.execute! { flunk "a duplicate must never execute" }
    assert_equal refusal.text, repeated.text
    assert_equal refusal.kind, repeated.kind
    assert_equal refusal.typed, repeated.typed
  end

  test "an interrupted worker's submission cannot replay uncertain effects" do
    submission = create(:playthrough_command, status: "running")
    assert_raises(Playthrough::Command::InterruptedError) do
      submission.execute! { flunk "an interrupted command must not replay" }
    end
  end

  test "a failed command is recorded and is never replayed by a redelivery" do
    submission = create(:playthrough_command)
    assert_raises(RuntimeError) { submission.execute! { raise "provider unavailable" } }
    assert_equal "failed", submission.reload.status
    assert_raises(Playthrough::Command::PreviouslyFailedError) do
      submission.execute! { flunk "a failed delivery must not execute again" }
    end
  end

  test "destroying a scene keeps its completed submission from replaying" do
    submission = create(:playthrough_command)
    scene = create(:scene, story: submission.playthrough.story)
    submission.execute! { scene }
    scene.destroy!

    assert_nil submission.reload.execute! { flunk "deleting prose cannot replay the action" }
    assert_predicate submission, :completed?
  end
end
