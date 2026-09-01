require "test_helper"

class TurnsControllerTest < ActionDispatch::IntegrationTest
  test "create hands the command back to the play page" do
    playthrough = create(:playthrough)

    post playthrough_turns_path(playthrough), params: { command: "  open the ledger  " }

    assert_redirected_to playthrough_path(playthrough, command: "open the ledger", anchor: "bottom")
  end

  test "create ignores an empty command" do
    playthrough = create(:playthrough)

    post playthrough_turns_path(playthrough), params: { command: "   " }

    assert_redirected_to playthrough_path(playthrough, anchor: "bottom")
  end

  # The anchor is the whole of the no-JS answer to "why did the page jump to
  # the top after I submitted?", so it is worth an assertion of its own rather
  # than riding along inside the two redirect paths above.
  test "create sends the player to the foot of the log" do
    playthrough = create(:playthrough)

    post playthrough_turns_path(playthrough), params: { command: "look around" }

    assert_match(/#bottom\z/, response.headers["Location"])
  end
end
