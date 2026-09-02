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

  test "says the turn did not finish, and that the story is still there" do
    assert_match(/did not finish/i, MESSAGE)
    assert_match(/nothing was lost/i, MESSAGE)
    assert_match(/where you left it/i, MESSAGE)
  end

  # It has to leave the player somewhere to go: the input comes back with it,
  # and trying again is the thing that actually works, since the failure is
  # usually one model having a bad turn.
  test "tells the player they can try again" do
    assert_match(/try again/i, MESSAGE)
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
