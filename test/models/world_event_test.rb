require "test_helper"

class WorldEventTest < ActiveSupport::TestCase
  def setup
    @story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    @mechanic = create(:world_mechanic, story: @story)
  end

  test "is valid with valid attributes" do
    assert build(:world_event, world_mechanic: @mechanic, story: @story).valid?
  end

  test "requires the story moment it happened at" do
    event = build(:world_event, world_mechanic: @mechanic, story: @story, occurred_at: nil)

    assert_not event.valid?
    assert_includes event.errors[:occurred_at], "can't be blank"
  end

  test "requires a summary" do
    event = build(:world_event, world_mechanic: @mechanic, story: @story, summary: nil)

    assert_not event.valid?
    assert_includes event.errors[:summary], "can't be blank"
  end

  test "records which places it touched" do
    event = create(:world_event, :with_locations, world_mechanic: @mechanic, story: @story)

    assert_equal 2, event.locations.count
    assert_includes event.locations.first.world_events, event
  end

  # `occurred_at` is story time, so `since` is asked in story time too.
  test "since returns the events from a story moment onwards, in story order" do
    early = create(:world_event, world_mechanic: @mechanic, story: @story, occurred_at: Time.utc(2026, 9, 1))
    late = create(:world_event, world_mechanic: @mechanic, story: @story, occurred_at: Time.utc(2026, 9, 3))

    assert_equal [ early, late ], @story.world_events.since(Time.utc(2026, 9, 1)).to_a
    assert_equal [ late ], @story.world_events.since(Time.utc(2026, 9, 2)).to_a
  end

  test "destroying a location it touched leaves the event" do
    event = create(:world_event, :with_locations, world_mechanic: @mechanic, story: @story)

    assert_no_difference -> { WorldEvent.count } do
      event.locations.first.destroy
    end

    assert_equal 1, event.reload.locations.count
  end

  test "destroying the story destroys its events" do
    create(:world_event, :with_locations, world_mechanic: @mechanic, story: @story)

    assert_difference -> { WorldEvent.count }, -1 do
      @story.destroy
    end
  end
end
