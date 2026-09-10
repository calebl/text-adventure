require "test_helper"
require "turbo/broadcastable/test_helper"

class TurnsControllerTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  test "only an acknowledged legacy interruption unblocks later play and keeps saved effects" do
    game = create(:playthrough, :started)
    coin = lying_here(game, game.current_location, name: "red coin")
    coin.update!(location: nil)
    old = create(:playthrough_command, playthrough: game, status: "running")
    later = create(:playthrough_command, playthrough: game, command: "/drop red coin")
    assert_raises(Playthrough::Command::InterruptedError) do
      Playthrough::Turn.new(game).play(later.command, request_token: later.request_token)
    end
    assert_equal "pending", later.reload.status
    assert_includes game.carried, coin
    post acknowledge_interruption_playthrough_turns_path(game), params: { command_id: old.id }
    assert_redirected_to playthrough_path(game, anchor: "bottom")
    assert_equal "interruption_acknowledged", old.reload.error_kind
    assert_equal "failed", old.status
    assert_includes game.carried, coin
    BaseAgent.stub(:new, FakeAgent.new("You put down the red coin.")) do
      Playthrough::Turn.new(game).play(later.command, request_token: later.request_token)
    end
    assert_equal game.current_location, coin.reload.location
    assert_predicate later.reload, :completed?
  end

  test "legacy acknowledgement cannot discard a recoverable turn or another game's command" do
    game = create(:playthrough)
    recoverable = create(:playthrough_command, playthrough: game, status: "running",
                         journal: { "version" => 1, "steps" => {} })
    post acknowledge_interruption_playthrough_turns_path(game), params: { command_id: recoverable.id }
    assert_equal "running", recoverable.reload.status

    other = create(:playthrough_command, status: "running")
    post acknowledge_interruption_playthrough_turns_path(game), params: { command_id: other.id }
    assert_response :not_found
    assert_equal "running", other.reload.status
  end

  test "create hands the turn to a job rather than running it in the request" do
    playthrough = create(:playthrough)

    assert_enqueued_with job: NarrationJob, args: [ playthrough.id, "open the ledger", "open-ledger" ] do
      post playthrough_turns_path(playthrough),
           params: { command: "  open the ledger  ", request_token: "open-ledger" }, as: :turbo_stream
    end
  end

  # No model is touched here at all, which is the whole point: the request that
  # accepts a command must not be the one that waits 20-30 seconds for a
  # narration. What it answers with is the spent token, replaced -- and nothing
  # that could stand in for the log.
  test "create acknowledges with a fresh token and no page that could overwrite a completed turn" do
    playthrough = create(:playthrough)

    post playthrough_turns_path(playthrough),
         params: { command: "open the ledger", request_token: "spent" }, as: :turbo_stream

    assert_response :success
    assert_equal [ ".request-token" ], token_streams.map { |stream| stream["targets"] }
    assert_not_includes response.body, "turn_log"
    assert_not_includes response.body, "what do you do?"
    assert_not_equal "spent", installed_token
  end

  # THE HALF THE COMPOSITE KEY CANNOT ANSWER. Two intentional "attack" lines
  # carry the same token until something re-mints it, and the job cannot: it
  # only re-renders the form once it owns the lock, which is exactly when the
  # player is typing again. So the accepted submission's own response spends the
  # token, and the repeat is a second turn.
  test "the same line submitted twice takes two turns because the token is spent on use" do
    playthrough = create(:playthrough)

    post playthrough_turns_path(playthrough),
         params: { command: "/attack Marek Sollen", request_token: "first-render" }, as: :turbo_stream
    second = installed_token

    assert_enqueued_with job: NarrationJob, args: [ playthrough.id, "/attack Marek Sollen", second ] do
      post playthrough_turns_path(playthrough),
           params: { command: "/attack Marek Sollen", request_token: second }, as: :turbo_stream
    end

    assert_equal 2, playthrough.commands.count
    assert_equal [ "/attack Marek Sollen" ], playthrough.commands.pluck(:command).uniq
  end

  # And the case the spent token must NOT turn into two turns: one submit whose
  # response never arrived, sent again with the token the browser still has.
  test "a resend of one submit that never got its reply is still one turn" do
    playthrough = create(:playthrough)

    assert_difference -> { playthrough.commands.count }, 1 do
      2.times do
        post playthrough_turns_path(playthrough),
             params: { command: "look around", request_token: "never-replaced" }, as: :turbo_stream
        assert_response :success
      end
    end
    assert_equal [ "never-replaced" ], enqueued_jobs.last(2).map { |job| job[:args].last }.uniq
  end

  test "a job finishing before the HTTP response cannot strand the browser in a pending turn" do
    playthrough = create(:playthrough, :started)
    item = lying_here(playthrough, playthrough.current_location, name: "red coin")
    immediate = ->(*arguments) { NarrationJob.perform_now(*arguments) }
    streams = capture_turbo_stream_broadcasts(playthrough) do
      BaseAgent.stub(:new, FakeAgent.new(RuntimeError.new("provider unavailable"))) do
        NarrationJob.stub(:perform_later, immediate) do
          post playthrough_turns_path(playthrough),
               params: { command: "/take red coin", request_token: "instant" }, as: :turbo_stream
        end
      end
    end

    assert_includes playthrough.reload.carried, item
    assert_equal "completed", playthrough.commands.sole.status
    assert_includes streams.first.to_html, 'id="stream"'
    assert_includes streams.last.to_html, "what do you do?"
    assert_response :success
    assert_equal [ ".request-token" ], token_streams.map { |stream| stream["targets"] },
                 "a late HTTP response may only re-mint the token"
    assert_not_includes response.body, "turn_log",
                        "a late HTTP response must have nothing that can replace the finished page"
  end

  test "create ignores an empty command" do
    playthrough = create(:playthrough)

    assert_no_enqueued_jobs only: NarrationJob do
      post playthrough_turns_path(playthrough), params: { command: "   " }, as: :turbo_stream
    end

    assert_redirected_to playthrough_path(playthrough)
  end

  # Scripts blocked, or the module still loading: the turn is enqueued either
  # way and the player reads it after a reload. `#bottom` is what puts them at
  # the foot of the log when they do.
  test "create still takes the turn without Turbo, and sends the player to the log" do
    playthrough = create(:playthrough)

    assert_enqueued_with job: NarrationJob, args: [ playthrough.id, "look around", "look-around" ] do
      post playthrough_turns_path(playthrough), params: { command: "look around", request_token: "look-around" }
    end

    assert_redirected_to playthrough_path(playthrough, anchor: "bottom")
  end
  # A BATTLE BUTTON IS THIS ROUTE WITH A FIXED COMMAND STRING, and that is the
  # whole of the one-UI argument for the panel: no second controller, no second
  # action, no payload but the line. The captain's call C9 of 2026-09-05 --
  # ***"go with buttons for now"***.
  #
  # The line is SLASHED, so `Playthrough::Grammar` reads it downstream and the
  # classifier is never called. Nothing here knows that; the string travels as
  # any typed line does, which is the point.
  test "a battle button's fixed command is an ordinary turn on the ordinary route" do
    playthrough = create(:playthrough)

    assert_enqueued_with job: NarrationJob, args: [ playthrough.id, "/attack Marek Sollen", "attack" ] do
      post playthrough_turns_path(playthrough),
           params: { command: "/attack Marek Sollen", request_token: "attack" }, as: :turbo_stream
    end

    # A panel puts every button on the page at once, so they all share whatever
    # token the acknowledgement installs -- which is why a submission is the
    # token AND the line, and why pressing two different buttons is two turns.
    assert_response :success
    assert_not_equal "attack", installed_token
  end


  # A form is only re-rendered when the job replaces `#turn_log`, and that
  # happens inside the playthrough's lock -- so a player whose previous turn is
  # still running is looking at a form whose token is already spent. The second
  # line they type is a second turn, and it used to be answered with a bare 409:
  # no job, no scene, no message, and nothing for Turbo to render.
  test "a second line typed into an already submitted form still takes its turn" do
    playthrough = create(:playthrough)
    post playthrough_turns_path(playthrough),
         params: { command: "look around", request_token: "one-form" }, as: :turbo_stream
    assert_response :success

    assert_enqueued_with job: NarrationJob, args: [ playthrough.id, "wait", "one-form" ] do
      post playthrough_turns_path(playthrough),
           params: { command: "wait", request_token: "one-form" }, as: :turbo_stream
    end

    assert_response :success
    assert_equal [ "look around", "wait" ], playthrough.commands.order(:id).pluck(:command)
  end

  private

  def token_streams
    Nokogiri::HTML.fragment(response.body).css("turbo-stream[action=replace]").to_a
  end

  def installed_token
    Nokogiri::HTML.fragment(response.body).at_css("input[name=request_token]")[:value]
  end
end
