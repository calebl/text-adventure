require "test_helper"

# WHAT A PLAYER READS WHEN A TURN DID NOT FINISH, pinned -- because the thing it
# replaced was an exception's `message`, and the way that regresses is by
# somebody deciding the player would like to know more.
class Playthrough::TurnFailureNoticeTest < ActiveSupport::TestCase
  MESSAGE = Playthrough::TurnFailureNotice::MESSAGE

  # THE POINT OF THE WHOLE THING. The copy is written once, for every reason a
  # turn can fail, so nothing internal can reach the page through it: no cap, no
  # model id, no class name, no fragment of an answer the app did not keep.
  test "says nothing about why, because every reason is an internal one" do
    assert_no_match(/\d/, MESSAGE, "a number here is an internal detail leaking")
    assert_no_match(/cap|schema|model|token|JSON|error|exception/i, MESSAGE)
  end

  test "says the turn did not finish and directs the player to what was actually saved" do
    assert_match(/did not finish/i, MESSAGE)
    assert_match(/log and your current possessions/i, MESSAGE)
    assert_match(/what was saved/i, MESSAGE)
    assert_no_match(/nothing was lost|where you left it/i, MESSAGE)
  end

  # An unexpected failure may follow an engine write. Asking for the same
  # action again without checking would invite repeating its effect.
  test "asks the player to inspect the saved state before choosing the next action" do
    assert_match(/check them before choosing your next action/i, MESSAGE)
    assert_no_match(/try again/i, MESSAGE)
  end

  # Nothing the player typed caused this, so it does not read as their fault.
  test "blames nobody and asks for nothing" do
    assert_no_match(/you (typed|did|should)/i, MESSAGE)
    assert_no_match(/invalid|unsupported|not allowed/i, MESSAGE)
  end

  # One line, because it sits in the `.alert` above the log rather than at the
  # foot of it. `Playthrough::SafetyNotice` is the long one, and the two are
  # deliberately not the same shape: that is an interception, this is a failure.
  test "stays to one short line" do
    assert_operator MESSAGE.length, :<, 260
    assert_not_equal Playthrough::SafetyNotice::HEADING, MESSAGE
  end
end
