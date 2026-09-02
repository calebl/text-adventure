require "test_helper"

# THE ONE THING IN HERE THAT DEPENDS ON A SETTING, and the reason it is a helper
# at all: with no retention cap there is no "older than N turns" to blame a
# missing conversation on, and interpolating a nil `Chat::KEEP_TURNS` into that
# sentence renders as a bug. See `Chat::KEEP_TURNS`.
class DebugHelperTest < ActionView::TestCase
  include DebugHelper

  test "with no cap set, pruning is not offered as an explanation" do
    assert_nil Chat::KEEP_TURNS, "the shipped default keeps everything"

    reason = no_receipts_reason

    assert_equal "no conversation kept — this Scene was written by something other than the loop", reason
    assert_no_match(/pruned/, reason)
    assert_no_match(/turns/, reason)
  end

  test "with a cap set, it names the cap and the variable that set it" do
    with_keep_turns(25) do
      reason = no_receipts_reason

      assert_match(/pruned after 25 turns/, reason)
      assert_match(/TA_CHAT_KEEP_TURNS/, reason)
      assert_match(/something other than the loop/, reason)
    end
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
