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

  # WHAT A READER SHOWING THE STREAM TO A PERSON ASKS FOR. `world_mechanic` is
  # nullable since a failed arc could write a row, so a call site that reaches
  # through it raises on exactly the kind of row it was made nullable for.
  test "an event says what wrote it without dereferencing a nullable mechanic" do
    mechanic = create(:world_event, story: @story)
    arc = create(:world_event, :a_failed_quest, story: @story)

    assert_equal mechanic.world_mechanic.name, mechanic.writer
    assert_nil arc.world_mechanic
    assert_equal "the story's arc", arc.writer
  end

  # THE WORLD'S ROWS PLUS ONE GAME'S, AND NO OTHER GAME'S -- the sentence in the
  # header, as a scope. A world event is everybody's; a failure is one player's.
  test "for_a_game returns the world's events and that game's own" do
    playing = create(:playthrough, story: @story)
    somebody_else = create(:playthrough, story: @story)

    world = create(:world_event, story: @story)
    mine = create(:world_event, :a_failed_quest, story: @story, playthrough: playing)
    theirs = create(:world_event, :a_failed_quest, story: @story, playthrough: somebody_else)

    found = @story.world_events.for_a_game(playing)

    assert_includes found, world
    assert_includes found, mine
    assert_not_includes found, theirs
  end
end
