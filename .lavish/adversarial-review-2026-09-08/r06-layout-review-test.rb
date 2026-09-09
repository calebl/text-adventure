require "test_helper"

class R06LayoutReviewTest < ActiveSupport::TestCase
  test "a failed container finalization is bypassed when the next move follows its relocated doorway" do
    game = create(:playthrough, :started)
    street = game.current_location
    place = create(:location, :stub, :with_a_footprint, story: game.story, name: "Workshop")
    create(:location_connection, location: street, connected_location: place)
    create(:location_connection, location: place, connected_location: street)
    detail = { "description" => "A brick workshop.", "lore" => "An old workshop.", "parameters" => {} }
    BaseAgent.stub(:new, FakeAgent.new(detail)) do
      Quest::Deadline.stub(:after_realizing!, ->(*) { raise IOError, "finalization interrupted" }) do
        assert_raises(IOError) { Playthrough::Turn.new(game).play("/move Workshop") }
      end
    end

    assert_equal street, game.reload.current_location
    assert_equal "exits_pending", place.reload.generation_checkpoint.fetch("phase")
    assert_predicate place, :stub?
    entry = street.exits.sole
    assert_equal place, entry.parent_location
    assert_not_equal place, entry

    room_detail = { "description" => "A low-ceilinged room.", "lore" => "The workroom.", "items" => [], "people" => [] }
    arrival = { "description" => "You reach the workroom.", "summary" => "You arrive." }
    BaseAgent.stub(:new, FakeAgent.new(room_detail, arrival)) do
      Playthrough::Turn.new(game).play("/move #{entry.name}")
    end

    assert_equal entry, game.reload.current_location
    assert_predicate entry.reload, :realized?
    assert_equal "exits_pending", place.reload.generation_checkpoint.fetch("phase")
    assert_predicate place, :stub?
  end
end
