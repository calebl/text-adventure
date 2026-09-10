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

  # A row a pre-journal worker left `running` has no receipts to replay from,
  # so the only honest answer is to stop: it is neither replayed nor completed.
  test "a legacy running row with no journal is interrupted rather than replayed" do
    submission = create(:playthrough_command, status: "running")
    assert_not_predicate submission, :recoverable?
    assert_predicate submission, :blocks_later?
    assert_raises(Playthrough::Command::InterruptedError) do
      submission.execute! { flunk "an interrupted command must not replay" }
    end
    assert_equal "running", submission.reload.status
  end

  test "a failure before any journal step is recorded and a redelivery raises instead of running it" do
    submission = create(:playthrough_command)
    assert_raises(RuntimeError) { submission.execute! { raise "provider unavailable" } }
    assert_equal "failed", submission.reload.status
    assert_empty submission.journal.fetch("steps")
    assert_not_predicate submission, :recoverable?
    assert_not_predicate submission, :blocks_later?
    assert_raises(Playthrough::Command::PreviouslyFailedError) do
      submission.execute! { flunk "a failed delivery must not execute again" }
    end
  end

  test "a failure after a committed effect keeps its receipt and finishes on redelivery" do
    submission = create(:playthrough_command)
    assert_raises(RuntimeError) do
      submission.execute! do
        Playthrough::Command::Journal.commit("take") { 7 }
        raise "provider unavailable"
      end
    end
    assert_equal "failed", submission.reload.status
    assert_predicate submission, :recoverable?
    assert_predicate submission, :blocks_later?

    replayed = submission.execute! do
      Playthrough::Command::Journal.commit("take") { flunk "a committed effect must not run twice" }
    end
    assert_equal 7, replayed
    assert_predicate submission.reload, :completed?
  end

  # --- what a row that did not finish means for the lines behind it -----------
  #
  # `blocks_later?` is the drain's question and `resume_target` is the page's;
  # both are read off the journal's KEYS, never off a label a worker wrote.

  test "a failed row whose journal stopped before any effect is recoverable but does not block" do
    submission = create(:playthrough_command, status: "failed", error_kind: "error",
                                              journal: journal_of(%w[already_over world_clock starting_room intent refusal origin round]))
    assert_predicate submission, :recoverable?
    assert_not_predicate submission, :blocks_later?
    assert_equal submission, Playthrough::Command.resume_target(submission.playthrough)
  end

  test "a failed row with a committed effect blocks every later line until it finishes" do
    %w[take drop throw attack arrival_cost character_effect narrated talked outcome].each do |effect|
      submission = create(:playthrough_command, status: "failed", error_kind: "error",
                                                journal: journal_of(%w[already_over origin] + [ effect ]))
      assert_predicate submission, :blocks_later?, "#{effect} is an effect the next line owes a finish to"
    end
  end

  test "a crisis failure and a pre-journal failure are neither recoverable nor blocking" do
    crisis = create(:playthrough_command, status: "failed", error_kind: "crisis", journal: journal_of(%w[take narrated]))
    legacy = create(:playthrough_command, status: "failed", error_kind: "error")
    [ crisis, legacy ].each do |row|
      assert_not_predicate row, :recoverable?
      assert_not_predicate row, :blocks_later?
      assert_nil Playthrough::Command.resume_target(row.playthrough)
    end
  end

  test "the oldest legacy running row is the resume target ahead of anything newer" do
    game = create(:playthrough)
    legacy = create(:playthrough_command, playthrough: game, status: "running")
    create(:playthrough_command, playthrough: game, status: "running", journal: journal_of(%w[take]))
    create(:playthrough_command, playthrough: game, command: "/wait")

    assert_equal legacy, Playthrough::Command.resume_target(game)
  end

  test "the newest unfinished row is the resume target when nothing legacy stands in front" do
    game = create(:playthrough)
    create(:playthrough_command, playthrough: game, status: "failed", error_kind: "error", journal: journal_of(%w[take]))
    newest = create(:playthrough_command, playthrough: game, command: "/wait")

    assert_equal newest, Playthrough::Command.resume_target(game)
  end

  test "a safe failure the game has moved past is overtaken and offers no resume" do
    game = create(:playthrough)
    stale = create(:playthrough_command, playthrough: game, status: "failed", error_kind: "error",
                                         journal: journal_of(%w[already_over world_clock starting_room]))
    create(:playthrough_command, playthrough: game, command: "/wait", status: "completed")

    assert_predicate stale, :overtaken?
    assert_nil Playthrough::Command.resume_target(game)
  end

  private

  def journal_of(steps)
    { "version" => 1, "steps" => steps.index_with(nil) }
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
