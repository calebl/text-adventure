require "test_helper"

class LocationTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @location = build(:location, :rivendell, story: @story)
  end

  test "should be valid with valid attributes" do
    assert @location.valid?
  end

  test "should require name" do
    @location.name = nil
    assert_not @location.valid?
    assert_includes @location.errors[:name], "can't be blank"
  end

  test "should require description" do
    @location.description = nil
    assert_not @location.valid?
    assert_includes @location.errors[:description], "can't be blank"
  end

  test "should require lore" do
    @location.lore = nil
    assert_not @location.valid?
    assert_includes @location.errors[:lore], "can't be blank"
  end

  test "should belong to story" do
    assert_equal @story, @location.story
  end

  test "should have many scenes" do
    @location.save!
    scene = create(:scene, :rivendell_arrival, story: @story, location: @location)
    assert_includes @location.scenes, scene
  end

  test "should have and belong to many connected locations" do
    @location.save!
    other_location = create(:location, :shire, story: @story)
    connection = create(:location_connection,
      location: @location,
      connected_location: other_location
    )

    @location.reload
    assert_includes @location.connected_locations, other_location
  end

  test "should track time since last visit" do
    @location.save!

    # No visit yet
    assert_nil @location.time_since_last_visit

    @location.update!(last_protagonist_visit: @story.start_time)

    assert_equal 90.minutes, @location.time_since_last_visit(@story.start_time + 90.minutes)
  end

  # THE WALL-CLOCK DEFECT, and the assertion that closes it. This used to be
  # `Time.current - last_protagonist_visit`, so a player who shut the tab for a
  # week and came back was told in fiction that they had been gone a week.
  test "time since last visit is measured in story time, not against the wall clock" do
    @location.save!
    @location.update!(last_protagonist_visit: @story.start_time)
    # Somewhere else, so the visit stamp this scene writes is not on @location.
    create(:scene, story: @story, location: create(:location, story: @story),
                   story_timestamp: @story.start_time + 20.minutes)

    travel 3.weeks do
      assert_equal 20.minutes, @location.time_since_last_visit,
                   "three weeks of somebody's life is not twenty minutes of the story"
    end
  end

  test "time since last visit defaults to the story's own clock" do
    @location.save!
    @location.update!(last_protagonist_visit: @story.start_time)
    create(:scene, story: @story, location: create(:location, story: @story),
                   story_timestamp: @story.start_time + 4.hours)

    assert_equal 4.hours, @location.time_since_last_visit
  end

  test "should mark protagonist visit at a story moment" do
    @location.save!
    at = @story.start_time + 3.hours

    @location.mark_protagonist_visit!(at)

    assert_equal at, @location.last_protagonist_visit
  end

  test "mobile and anchored scope the places that move" do
    @location.save!
    mover = create(:location, story: @story, name: "The Travelling Stair", mobile: true)

    assert_includes Location.mobile, mover
    assert_not_includes Location.mobile, @location
    assert_includes Location.anchored, @location
    assert_not_includes Location.anchored, mover
  end

  test "a location does not move by default" do
    assert_not Location.new.mobile?
  end

  test "defaults to a stub" do
    assert Location.new.stub?
  end

  test "a stub saves without a description or lore" do
    stub = build(:location, :stub, story: @story, name: "The Long Stair")

    assert stub.valid?
    assert stub.save
    assert stub.stub?
  end

  test "a realized location still requires a description and lore" do
    realized = build(:location, :stub, story: @story, detail_level: "realized")

    assert_not realized.valid?
    assert_includes realized.errors[:description], "can't be blank"
    assert_includes realized.errors[:lore], "can't be blank"
  end

  test "a stub still requires a name" do
    stub = build(:location, :stub, story: @story, name: nil)

    assert_not stub.valid?
    assert_includes stub.errors[:name], "can't be blank"
  end

  test "rejects a detail level it does not know" do
    location = build(:location, story: @story)
    location.detail_level = "half"

    assert_not location.valid?
    assert_includes location.errors[:detail_level], "is not included in the list"
  end

  test "scopes locations by detail level" do
    stub = create(:location, :stub, story: @story)
    realized = create(:location, story: @story)

    assert_includes Location.stubs, stub
    assert_not_includes Location.stubs, realized
    assert_includes Location.realized, realized
    assert_not_includes Location.realized, stub
  end

  test "exits are the locations connected out of here" do
    @location.save!
    neighbour = create(:location, :stub, story: @story)
    create(:location_connection, location: @location, connected_location: neighbour)

    assert_includes @location.reload.exits, neighbour
  end

  # ------------------------------------------------------------------------
  # DANGER: HOW LIKELY THIS PLACE IS TO BE BORN WITH THE WORLD'S MONSTERS IN IT.
  # A closed-set key into `Location::DANGERS`, the shape
  # `LocationConnection::DISTANCES` has -- the labels are what an author reads,
  # the numbers are what the engine rolls.

  test "a room is safe unless a world says otherwise" do
    assert_equal Location::SAFE, build(:location).danger
    assert_not_predicate build(:location), :dangerous?
    assert_equal 0, build(:location).danger_share
  end

  test "should refuse a danger the engine has no table for" do
    @location.danger = "a bit worrying"

    assert_not @location.valid?
    assert_includes @location.errors[:danger], "is not included in the list"
  end

  test "should refuse a blank danger" do
    @location.danger = nil

    assert_not @location.valid?
  end

  test "the share is faces of the danger die, and safe throws none" do
    assert_equal 0, Location::DANGERS.fetch(Location::SAFE)
    assert_equal Location::DANGER_DIE, Location::DANGERS.fetch("deadly")
    Location::DANGERS.each_value { |share| assert_includes 0..Location::DANGER_DIE, share }
  end

  test "an unknown danger reads as no share at all rather than raising" do
    room = build(:location)
    room.danger = "unheard-of"

    assert_equal 0, room.danger_share
    assert_not_predicate room, :dangerous?
  end

  test "the dangerous scope is every room that is not safe" do
    @location.save!
    dangerous = create(:location, :dangerous, story: @story, name: "The Bell Chamber")
    create(:location, :deadly, story: @story, name: "The Sump")

    assert_equal 2, @story.locations.dangerous.count
    assert_includes @story.locations.dangerous, dangerous
    assert_not_includes @story.locations.dangerous, @location
  end

  test "should have parent location relationship" do
    @location.save!
    child_location = create(:location,
      story: @story,
      name: "Elrond's Library",
      parent_location: @location
    )

    assert_equal @location, child_location.parent_location
  end
end
