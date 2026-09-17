require "test_helper"

class WorldMechanic::PhysicalSweepTest < ActiveSupport::TestCase
  test "a browser walk keeps an opened moving door separate from the other game's lock" do
    path = EngineSweep::DIRECTORY.join("a-moving-door-keeps-its-lock.yml")
    result = EngineSweep::Walk.new(EngineSweep::Script.load(path)).play

    assert result.passed?, result.report
  end
end
