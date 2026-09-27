require "test_helper"

class Playthrough::TurnEventTest < ActiveSupport::TestCase
  test "events number themselves per turn from one" do
    first = create(:playthrough_command)
    second = create(:playthrough_command)

    a = Playthrough::TurnEvent.append!(first, "started", { "turn" => "1" })
    b = Playthrough::TurnEvent.append!(first, "prose", { "text" => "x" })
    c = Playthrough::TurnEvent.append!(second, "started", { "turn" => "2" })

    assert_equal [ 1, 2, 1 ], [ a, b, c ].map(&:sequence)
    assert_equal [ b ], first.turn_events.after(1).to_a
  end

  test "a kind outside the protocol's list is refused" do
    assert_not build(:playthrough_turn_event, kind: "chunk").valid?
  end

  test "a turn's events go with the turn" do
    event = create(:playthrough_turn_event)
    event.command.destroy!
    assert_not Playthrough::TurnEvent.exists?(event.id)
  end
end
