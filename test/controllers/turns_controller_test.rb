require "test_helper"

class TurnsControllerTest < ActionDispatch::IntegrationTest
  test "create hands the turn to a job rather than running it in the request" do
    playthrough = create(:playthrough)

    assert_enqueued_with job: NarrationJob, args: [ playthrough.id, "open the ledger" ] do
      post playthrough_turns_path(playthrough),
           params: { command: "  open the ledger  " }, as: :turbo_stream
    end
  end

  # No model is touched here at all, which is the whole point: the request that
  # accepts a command must not be the one that waits 20-30 seconds for a
  # narration.
  test "create answers immediately with the streaming half of the page" do
    playthrough = create(:playthrough)

    post playthrough_turns_path(playthrough),
         params: { command: "open the ledger" }, as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match 'action="replace"', response.body
    assert_match 'target="turn_log"', response.body
    assert_match "&gt; open the ledger", response.body
    assert_match 'id="stream"', response.body
  end

  # The dimming rule is `.log:not(.streaming) > .turn:last-of-type`, so while a
  # turn is in flight the log has to say it is not the newest thing on the page
  # -- the #stream div below it is.
  test "create marks the log as streaming and takes the input away" do
    playthrough = create(:playthrough, :in_scene)

    post playthrough_turns_path(playthrough),
         params: { command: "open the ledger" }, as: :turbo_stream

    assert_match 'class="log streaming"', response.body
    assert_no_match(/what do you do\?/, response.body)
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

    assert_enqueued_with job: NarrationJob, args: [ playthrough.id, "look around" ] do
      post playthrough_turns_path(playthrough), params: { command: "look around" }
    end

    assert_redirected_to playthrough_path(playthrough, anchor: "bottom")
  end
end
