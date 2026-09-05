require "test_helper"

# `distance` and `travel_method` come from fixed tables, and `time_to_travel`
# is derived from them. The point of all three is that connections are written
# in BOTH directions from one model answer, so anything directional or
# free-form is wrong on the way back.
class LocationConnectionTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @here = create(:location, story: @story, name: "Grenn's Boarding House")
    @there = create(:location, story: @story, name: "Mournwell Lane")
  end

  def connection(**attributes)
    build(:location_connection, location: @here, connected_location: @there, **attributes)
  end

  test "is valid with a distance and travel method from the tables" do
    assert connection(distance: "a short walk", travel_method: "walking").valid?
  end

  test "rejects a distance that is not one of the known ones" do
    row = connection(distance: "80 meters")

    assert_not row.valid?
    assert_includes row.errors[:distance], "is not included in the list"
  end

  # This is the field that produced "maybe a minute's climb down the rains" --
  # free prose truncated mid-word by a 60 character cap.
  test "rejects a travel method that is not one of the known ones" do
    row = connection(travel_method: "climb down the drainpipe to the lane below")

    assert_not row.valid?
    assert_includes row.errors[:travel_method], "is not included in the list"
  end

  test "derives time_to_travel rather than accepting one" do
    row = connection(distance: "adjacent", travel_method: "walking",
                     time_to_travel: "three and a half fortnights")
    row.valid?

    assert_equal "about a minute", row.time_to_travel
  end

  test "a longer distance takes longer than a shorter one by the same method" do
    short = connection(distance: "a short walk", travel_method: "walking")
    long = connection(distance: "a long journey", travel_method: "walking")

    assert_operator LocationConnection.travel_minutes(short.distance, short.travel_method),
                    :<,
                    LocationConnection.travel_minutes(long.distance, long.travel_method)
  end

  test "a slower method takes longer than a faster one over the same distance" do
    assert_operator LocationConnection.travel_minutes("across the district", "riding"),
                    :<,
                    LocationConnection.travel_minutes("across the district", "crawling")
  end

  test "humanizes the whole range without producing a bare number" do
    LocationConnection::DISTANCES.each_key do |distance|
      LocationConnection::TRAVEL_METHODS.each_key do |method|
        phrase = LocationConnection.humanize_minutes(
          LocationConnection.travel_minutes(distance, method)
        )

        assert phrase.present?, "#{distance} by #{method} produced nothing"
        assert_match(/minute|hour|day/, phrase, "#{distance} by #{method} -> #{phrase}")
      end
    end
  end

  test "travel_minutes is nil for values outside the tables" do
    assert_nil LocationConnection.travel_minutes("80 meters", "walking")
    assert_nil LocationConnection.travel_minutes("adjacent", "wading")
  end

  # The whole reason the values are direction-neutral. Location::Generator
  # writes both rows from one answer; if a value only reads correctly one way,
  # the world records a lie about the way back.
  test "the same values are valid and identical in both directions" do
    there_and_back = LocationConnection::DISTANCES.keys.product(LocationConnection::TRAVEL_METHODS.keys)

    there_and_back.each do |distance, method|
      forward = build(:location_connection, location: @here, connected_location: @there,
                                            distance: distance, travel_method: method)
      backward = build(:location_connection, location: @there, connected_location: @here,
                                             distance: distance, travel_method: method)

      assert forward.valid?, "#{distance} by #{method} is invalid going out"
      assert backward.valid?, "#{distance} by #{method} is invalid coming back"
      assert_equal forward.time_to_travel, backward.time_to_travel
    end
  end

  # Nothing in the tables says "up", "down", "in" or "out".
  test "no travel method names a direction" do
    LocationConnection::TRAVEL_METHODS.each_key do |method|
      assert_no_match(/\b(up|down|in|out|back|toward|away)\b/i, method)
    end
  end

  test "requires both ends" do
    assert_not LocationConnection.new(distance: "adjacent", travel_method: "walking").valid?
  end

  test "one pair of locations gets one row per direction" do
    create(:location_connection, location: @here, connected_location: @there)
    duplicate = connection

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:location_id], "has already been taken"
  end

  test "from_location and to_location select the right direction" do
    row = create(:location_connection, location: @here, connected_location: @there)

    assert_includes LocationConnection.from_location(@here), row
    assert_includes LocationConnection.to_location(@there), row
    assert_empty LocationConnection.from_location(@there)
  end

  # ------------------------------------------------------------------------
  # WHAT WALKING THIS WAY COSTS, and the first mechanic that WANTS the directed
  # edge: a door is two rows, so a hazard on one of them is one-way by
  # construction and nothing has to enforce it.

  test "a doorway has no hazard by default" do
    edge = create(:location_connection)

    assert_nil edge.hazard
    assert_not edge.hazardous?
    assert_nil edge.hazard_entry
  end

  test "a hazard has to be one of the catalogue's keys and one of the engine's dice" do
    assert_not build(:location_connection, hazard: "haunted", hazard_die: 4).valid?
    assert_not build(:location_connection, hazard: "drop", hazard_die: 7).valid?
  end

  test "half a hazard is refused, either half" do
    assert_not build(:location_connection, hazard: "drop").valid?
    assert_not build(:location_connection, hazard_die: 4).valid?
  end

  # THE WHOLE POINT: `.walked` reads ONE row, so the cost is on the direction
  # and the door still leads both ways.
  test "the hazard is on the direction that was walked and not on the door" do
    court = create(:location, name: "The Causeway Court")
    hulk = create(:location, story: court.story, name: "The Vestry Hulk")
    create(:location_connection, :hazardous, location: court, connected_location: hulk)
    create(:location_connection, location: hulk, connected_location: court)

    assert LocationConnection.walked(court, hulk).hazardous?
    assert_not LocationConnection.walked(hulk, court).hazardous?
    assert_includes court.exits, hulk, "a one-way hazard is not a one-way exit"
    assert_includes hulk.exits, court
  end

  test "walked answers nothing for a pair with no doorway" do
    assert_nil LocationConnection.walked(create(:location), create(:location))
    assert_nil LocationConnection.walked(nil, create(:location))
  end

  test "every catalogue entry names a save and its words" do
    LocationConnection::HAZARDS.each do |key, entry|
      assert entry.key?(:save), "#{key} has no `save:` -- nil is a value and an omission is not"
      assert entry[:save].nil? || Character::ABILITIES.include?(entry[:save]),
             "#{key} saves on something that is not one of Character::ABILITIES"
      assert entry[:words].present?, "#{key} has nothing to tell the prose"
    end
  end
end
