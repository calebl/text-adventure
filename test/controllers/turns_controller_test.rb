require "test_helper"

class TurnsControllerTest < ActionDispatch::IntegrationTest
  test "create hands the command back to the play page" do
    playthrough = create(:playthrough)

    post playthrough_turns_path(playthrough), params: { command: "  open the ledger  " }

    assert_redirected_to playthrough_path(playthrough, command: "open the ledger")
  end

  test "create ignores an empty command" do
    playthrough = create(:playthrough)

    post playthrough_turns_path(playthrough), params: { command: "   " }

    assert_redirected_to playthrough_path(playthrough)
  end
end
