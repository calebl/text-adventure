require "test_helper"

class WorldMechanicTest < ActiveSupport::TestCase
  def setup
    @story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
  end

  test "is valid with valid attributes" do
    assert build(:world_mechanic, story: @story).valid?
  end

  test "requires a name" do
    mechanic = build(:world_mechanic, story: @story, name: nil)

    assert_not mechanic.valid?
    assert_includes mechanic.errors[:name], "can't be blank"
  end

  # The natural key WorldSeed::Loader matches on, so a duplicate would make
  # re-seeding ambiguous as well as wrong.
  test "names are unique within a story" do
    create(:world_mechanic, story: @story, name: "The nightly rearrangement")
    duplicate = build(:world_mechanic, story: @story, name: "The nightly rearrangement")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "the same name in another story is fine" do
    create(:world_mechanic, story: @story, name: "The nightly rearrangement")

    assert build(:world_mechanic, story: create(:story), name: "The nightly rearrangement").valid?
  end

  # The whole point of the fixed tables: a world supplies parameters, and a
  # parameter that is not in the catalogue is rejected rather than guessed at.
  test "kind must be in the catalogue" do
    mechanic = build(:world_mechanic, story: @story, kind: "teleport_the_player")

    assert_not mechanic.valid?
    assert_includes mechanic.errors[:kind], "is not included in the list"
  end

  test "cadence must be one of the known cadences" do
    mechanic = build(:world_mechanic, story: @story, cadence: "whenever it feels like it")

    assert_not mechanic.valid?
    assert_includes mechanic.errors[:cadence], "is not included in the list"
  end

  test "operation resolves the kind to the Ruby class that implements it" do
    mechanic = create(:world_mechanic, story: @story)

    assert_instance_of WorldMechanic::ShuffleConnections, mechanic.operation
  end

  test "destroying it destroys its events" do
    mechanic = create(:world_mechanic, story: @story)
    create(:world_event, world_mechanic: mechanic, story: @story)

    assert_difference -> { WorldEvent.count }, -1 do
      mechanic.destroy
    end
  end

  # THE BUG THE SPIKE FOUND. A cadence is a boundary in the story's DAY, not an
  # interval from `start_time`. This story opens at 23:00; a 1,440-minute
  # interval would put its first night 23 hours late.
  test "a nightly cadence fires at midnight, not a day after the story starts" do
    mechanic = create(:world_mechanic, story: @story, cadence: "nightly")

    boundaries = mechanic.pending_boundaries(@story.start_time + 2.hours)

    assert_equal [ Time.utc(2026, 9, 1, 0, 0, 0) ], boundaries
  end

  test "nothing is pending before the first boundary" do
    mechanic = create(:world_mechanic, story: @story, cadence: "nightly")

    assert_empty mechanic.pending_boundaries(@story.start_time + 40.minutes)
  end

  test "nothing is pending for a clock that has not moved" do
    mechanic = create(:world_mechanic, story: @story, cadence: "nightly")

    assert_empty mechanic.pending_boundaries(@story.start_time)
  end

  test "an hourly cadence fires on the hour" do
    mechanic = create(:world_mechanic, story: @story, cadence: "hourly")

    boundaries = mechanic.pending_boundaries(@story.start_time + 150.minutes)

    assert_equal [ Time.utc(2026, 9, 1, 0, 0, 0), Time.utc(2026, 9, 1, 1, 0, 0) ], boundaries
  end

  # CATCHING UP is the property that makes this dependable rather than a timer:
  # nothing has to be running for the nights to happen, they are simply owed.
  test "every boundary passed while nobody was looking is pending at once" do
    mechanic = create(:world_mechanic, story: @story, cadence: "nightly")

    boundaries = mechanic.pending_boundaries(@story.start_time + 3.days + 30.minutes)

    assert_equal 3, boundaries.size
    assert_equal Time.utc(2026, 9, 1, 0, 0, 0), boundaries.first
    assert_equal Time.utc(2026, 9, 3, 0, 0, 0), boundaries.last
  end

  test "boundaries already run are not pending again" do
    mechanic = create(:world_mechanic, story: @story, cadence: "nightly",
                                       last_run_at: Time.utc(2026, 9, 2, 0, 0, 0))

    boundaries = mechanic.pending_boundaries(Time.utc(2026, 9, 3, 12, 0, 0))

    assert_equal [ Time.utc(2026, 9, 3, 0, 0, 0) ], boundaries
  end

  test "catch_up! stamps last_run_at with the last boundary it ran" do
    story = shufflable_story
    mechanic = story.world_mechanics.first
    advance(story, 2.days + 30.minutes)

    mechanic.catch_up!(story.clock)

    assert_equal Time.utc(2026, 9, 2, 0, 0, 0), mechanic.reload.last_run_at
  end

  # IDEMPOTENT BECAUSE `last_run_at` IS A COLUMN. This is the assertion a
  # restart rests on: a second process, or a second turn, must not replay a
  # night that has already happened.
  test "catching up twice runs nothing the second time" do
    story = shufflable_story
    advance(story, 2.days + 30.minutes)

    first = story.catch_up_world!
    assert_equal 2, first.size

    assert_no_difference -> { WorldEvent.count } do
      assert_empty story.catch_up_world!
    end
  end

  test "catch_up_story! runs every mechanic the story has" do
    story = shufflable_story
    create(:world_mechanic, story: story, name: "The hourly bells", cadence: "hourly")
    advance(story, 90.minutes)

    WorldMechanic.catch_up_story!(story)

    assert_equal Time.utc(2026, 9, 1, 0, 0, 0), story.world_mechanics.order(:id).first.last_run_at
    assert_equal Time.utc(2026, 9, 1, 0, 0, 0), story.world_mechanics.order(:id).last.last_run_at
  end

  test "a story with no mechanics catches up to nothing" do
    assert_empty @story.catch_up_world!
  end

  # No model call anywhere on the path, which is the claim the whole slice rests
  # on. `BaseAgent` is the only door to a model in this app, so stubbing it to
  # flunk is the whole proof.
  test "catching up asks no model anything" do
    story = shufflable_story
    advance(story, 2.days)

    BaseAgent.stub(:new, -> { flunk "the world mechanic asked a model something" }) do
      assert_not_empty story.catch_up_world!
    end
  end

  private

  # A quarter that travels: three mobile places, each with one edge out to a
  # fixed landmark, plus a hub joining the mobile ones together.
  def shufflable_story
    story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    hub = create(:location, story: story, name: "Room 3", mobile: true)
    movers = 3.times.map { |n| create(:location, story: story, name: "Mobile #{n}", mobile: true) }
    anchors = 3.times.map { |n| create(:location, story: story, name: "Landmark #{n}") }

    movers.each { |mover| connect(hub, mover) }
    movers.zip(anchors).each { |mover, anchor| connect(mover, anchor) }
    create(:world_mechanic, story: story, name: "The nightly rearrangement")

    story
  end

  def connect(from, to)
    [ [ from, to ], [ to, from ] ].each do |origin, destination|
      create(:location_connection, location: origin, connected_location: destination,
                                   distance: "a short walk", travel_method: "walking")
    end
  end

  def advance(story, by)
    create(:scene, story: story, location: story.locations.first,
                   story_timestamp: story.start_time + by)
  end
end
