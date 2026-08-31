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

    # Mark a visit
    past_time = 1.hour.ago
    @location.update!(last_protagonist_visit: past_time)

    time_diff = @location.time_since_last_visit
    assert time_diff > 0
    assert time_diff < 2.hours
  end

  test "should mark protagonist visit" do
    @location.save!

    freeze_time do
      @location.mark_protagonist_visit!
      assert_equal Time.current, @location.last_protagonist_visit
    end
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
