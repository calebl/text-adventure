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

  # --- A ROW ABOUT THE FUTURE (the captain's Call 8, 2026-09-06) -------------

  test "a row with no due hour is a thing that has happened" do
    event = create(:world_event, story: @story, world_mechanic: @mechanic)

    assert_not event.scheduled?
    assert_not event.pending?
    assert_equal event.occurred_at, event.happened_at
  end

  test "a scheduled row has not happened until it fires" do
    event = create(:world_event, :scheduled, story: @story)

    assert event.scheduled?
    assert event.pending?
    assert_nil event.happened_at

    event.fire!(at: @story.start_time + 70.minutes)

    assert_not event.pending?
    assert_equal @story.start_time + 70.minutes, event.happened_at
  end

  # WHY IT IS A MOMENT AND NOT A FLAG: the clock only moves when somebody plays,
  # so a row due at 23:05 can be fired at 23:10 and the gap is a fact about this
  # world rather than rounding.
  test "firing records when the engine reached the hour, not when the hour was" do
    event = create(:world_event, :scheduled, story: @story)
    event.fire!(at: @story.start_time + 70.minutes)

    assert_equal @story.start_time + 1.hour, event.scheduled_for
    assert_equal @story.start_time + 70.minutes, event.fired_at
  end

  test "firing twice keeps the moment it fired at" do
    event = create(:world_event, :fired, story: @story)
    was = event.fired_at

    event.fire!(at: @story.start_time + 10.hours)

    assert_equal was, event.reload.fired_at
  end

  test "a row that was never due cannot have fired" do
    event = build(:world_event, story: @story, world_mechanic: @mechanic, fired_at: @story.start_time)

    assert_not event.valid?
    assert_includes event.errors[:fired_at], "must be blank"
  end

  test "due_by is this story's unfired rows at or before a moment, oldest first" do
    soon = create(:world_event, :scheduled, story: @story, summary: "soon",
                                            scheduled_for: @story.start_time + 5.minutes)
    later = create(:world_event, :scheduled, story: @story, summary: "later",
                                             scheduled_for: @story.start_time + 8.hours)
    already = create(:world_event, :fired, story: @story, summary: "already",
                                           scheduled_for: @story.start_time + 1.minute)

    due = @story.world_events.due_by(@story.start_time + 10.minutes)

    assert_equal [ soon ], due.to_a
    assert_not_includes due, later
    assert_not_includes due, already
  end

  test "happened and pending split the stream between them" do
    past = create(:world_event, story: @story, world_mechanic: @mechanic)
    coming = create(:world_event, :scheduled, story: @story, summary: "coming")
    gone_off = create(:world_event, :fired, story: @story, summary: "gone off")

    assert_equal [ past, gone_off ].sort_by(&:id), @story.world_events.happened.order(:id).to_a
    assert_equal [ coming ], @story.world_events.pending.to_a
  end
end
