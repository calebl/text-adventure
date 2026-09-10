require "test_helper"

class GameLockTest < ActiveSupport::TestCase
  test "an exception releases the process claim and nested entry refuses instead of deadlocking" do
    assert_raises(RuntimeError) do
      GameLock.synchronize("test", 1) { raise "stop" }
    end
    GameLock.synchronize("test", 1) do
      assert_raises(GameLock::ReentrantError) { GameLock.synchronize("test", 1) { flunk } }
      assert_equal :separate, GameLock.synchronize("location", 1) { :separate }
    end
    assert_equal :released, GameLock.synchronize("test", 1) { :released }
  end
end
