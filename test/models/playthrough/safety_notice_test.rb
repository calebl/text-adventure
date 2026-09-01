require "test_helper"

# WHAT A PERSON IN DISTRESS READS, pinned. The four rules in the class comment
# are the reason each of these tests exists; a change that breaks one of them is
# a change to something somebody may be reading at the worst moment of their
# week, so it should have to be made on purpose.
class Playthrough::SafetyNoticeTest < ActiveSupport::TestCase
  def text
    [ Playthrough::SafetyNotice::HEADING, *Playthrough::SafetyNotice::PARAGRAPHS ].join(" ")
  end

  # THE ONE THAT MATTERS MOST. The player's country is not known -- there is no
  # location on a `Playthrough` -- and a crisis number that is wrong for where
  # somebody is standing is worse than none at all. So the message names no
  # number, and this is what stops a well-meaning change adding one.
  test "names no phone number, because it does not know where the player is" do
    assert_no_match(/\d/, text, "a digit here is a resource being guessed at")
  end

  test "says it is the app talking before it says anything else" do
    assert_match(/not a character/, Playthrough::SafetyNotice::HEADING)
  end

  # It names no number and still has to be useful, so it has to say how to find
  # the right one -- and why it is not guessing.
  test "says how to find the right resource, and why it is not printing one" do
    assert_match(/crisis line/i, text)
    assert_match(/we do not know where you are/i, text)
  end

  # Short, and not clinical. It diagnoses nothing and it does not treat the
  # command the player typed as evidence about them: a grim game invites grim
  # commands, and what triggered this was the MODEL's answer.
  test "stays short and diagnoses nothing" do
    assert_operator text.length, :<, 800
    assert_equal 3, Playthrough::SafetyNotice::PARAGRAPHS.size
    assert_no_match(/you are (feeling|having|experiencing)/i, text)
  end

  test "does not end the playthrough or take the story away" do
    assert_match(/nothing was lost/i, text)
    assert_match(/where you left it/i, text)
  end
end
