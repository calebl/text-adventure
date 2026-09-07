require "test_helper"

# THE GUARANTEE, AND IT IS AN ENGINE RULE RATHER THAN A PROMPT.
#
# The captain's Call 1 of 2026-09-06 -- a generated story must ALWAYS be
# completable -- and his Call 2 -- the engine may place a target the model
# declined to place, on a deadline, through the ordinary stub path. What these
# pin is when it fires, what it builds, and the three things it must not do:
# fire early, place beside the reachable set, or bolt a person onto the graph.
#
# NO MODEL CALL ANYWHERE IN THIS FILE, which is the whole claim: every one of
# these runs offline, and `test_helper` has no key.
class Quest::DeadlineTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @gate = create(:location, :realized, story: @story, name: "Iron Gate Chamber")
    @quest = create(:quest, :generated, story: @story, title: "The Long Way Down")
    create(:quest_outcome, :default, quest: @quest, name: "rescued")
  end

  # --- when ------------------------------------------------------------------

  test "the phases are named and counted in rooms opened" do
    assert_equal 1, Quest::Deadline.rooms_opened(@story), "the opening room is the first room opened"
    assert_equal "asking", Quest::Deadline.phase_for(@story)
    assert_not Quest::Deadline.overdue?(@story)

    open_rooms(Quest::Deadline::GRACE_ROOMS - 1)

    assert_equal Quest::Deadline::GRACE_ROOMS, Quest::Deadline.rooms_opened(@story)
    assert_equal "asking", Quest::Deadline.phase_for(@story),
                 "the grace is inclusive: the last room inside it is still the model's to answer"

    open_rooms(1)

    assert_equal "placing", Quest::Deadline.phase_for(@story)
    assert Quest::Deadline.overdue?(@story)
  end

  test "nothing is placed while the world is still inside its grace" do
    create(:quest_step, :reach_location, quest: @quest, position: 1, target_name: "Blackfang Warren")

    assert_no_difference "Location.count" do
      Quest::Deadline.after_realizing!(@gate)
    end
  end

  test "a world with no arc is never touched" do
    @quest.destroy
    open_rooms(Quest::Deadline::GRACE_ROOMS + 1)

    assert_no_difference "Location.count" do
      Quest::Deadline.after_realizing!(@gate)
    end
  end

  test "a step the world already grew is not placed again" do
    step = create(:quest_step, :reach_location, quest: @quest, position: 1, target_name: "Blackfang Warren")
    step.bind!(create(:location, story: @story, name: "Blackfang Warren"), at: @story.start_time)
    open_rooms(Quest::Deadline::GRACE_ROOMS + 1)

    assert_no_difference "Location.count" do
      Quest::Deadline.after_realizing!(@gate)
    end
  end

  test "a time_passed step is never placed -- the clock already exists" do
    create(:quest_step, quest: @quest, position: 1, minutes: 40)
    open_rooms(Quest::Deadline::GRACE_ROOMS + 1)

    assert_no_difference "Location.count" do
      Quest::Deadline.after_realizing!(@gate)
    end
  end

  # --- a place ---------------------------------------------------------------

  test "a place target is built as a place with an inside, wired into the reachable set" do
    step = create(:quest_step, :reach_location, quest: @quest, position: 1,
                               target_name: "Blackfang Warren", teaser: "a hole cut down out of the rock")
    deepest = open_rooms(Quest::Deadline::GRACE_ROOMS + 1).last

    Quest::Deadline.after_realizing!(deepest)

    warren = @story.locations.find_by(name: "Blackfang Warren")

    assert_not_nil warren
    assert_predicate warren, :laid_out?
    assert_equal warren, step.reload.target
    assert_equal "a hole cut down out of the rock", warren.teaser
  end

  test "the way in lands on a room of it and never on the container" do
    create(:quest_step, :reach_location, quest: @quest, position: 1, target_name: "Blackfang Warren")
    deepest = open_rooms(Quest::Deadline::GRACE_ROOMS + 1).last

    Quest::Deadline.after_realizing!(deepest)
    warren = @story.locations.find_by(name: "Blackfang Warren")

    assert_empty LocationConnection.from_location(warren).to_a,
                 "a laid-out place is never an endpoint (Call 5, 2026-09-07)"
    assert_includes Location::Interior.entry_room(warren).exits, deepest
    assert_includes deepest.reload.exits, Location::Interior.entry_room(warren)
  end

  test "the place it builds can descend, because the engine asked for cellars" do
    create(:quest_step, :reach_location, quest: @quest, position: 1, target_name: "Blackfang Warren")
    deepest = open_rooms(Quest::Deadline::GRACE_ROOMS + 1).last

    Quest::Deadline.after_realizing!(deepest)
    warren = @story.locations.find_by(name: "Blackfang Warren")

    assert_operator warren.child_locations.minimum(:z), :<, 0,
                    "BASEMENTS is zero-weighted, so an interior descends only when a caller asks"
  end

  # --- a person, and the prince ruling ---------------------------------------

  test "a person target stands in a room inside a place, never in a stub of their own" do
    step = create(:quest_step, :speak_to, quest: @quest, position: 1, target_name: "Prince Aurel Durn")
    deepest = open_rooms(Quest::Deadline::GRACE_ROOMS + 1).last

    Quest::Deadline.after_realizing!(deepest)

    prince = @story.characters.find_by(fullname: "Prince Aurel Durn")

    assert_not_nil prince
    assert_equal prince, step.reload.target

    cell = prince.location

    assert_not_nil cell.parent_location, "the prince is in a Room inside a Location (2026-09-06)"
    assert_predicate cell.parent_location, :laid_out?
  end

  # THE RUNG THAT MAKES THE COMMON CASE FREE. A generated arc names a place and a
  # person both, so the place beat is usually answered before the person beat
  # comes due -- and raising a second building beside the first would be worse in
  # every way than using the one the story already named.
  test "a building the world already has is used rather than a second one raised beside it" do
    create(:quest_step, :speak_to, quest: @quest, position: 1, target_name: "Prince Aurel Durn")
    deepest = open_rooms(Quest::Deadline::GRACE_ROOMS + 1).last
    warren = create(:location, story: @story, name: "Blackfang Warren", width: 12, depth: 10)
    Location::Interior.lay_out!(warren)
    connect!(deepest, Location::Interior.entry_room(warren))

    assert_difference "Location.where(parent_location_id: nil).count", 0 do
      Quest::Deadline.after_realizing!(deepest)
    end

    prince = @story.characters.find_by(fullname: "Prince Aurel Durn")

    assert_equal warren, prince.location.parent_location
    assert_nil @story.locations.find_by(name: "where Prince Aurel Durn is")
  end

  test "the person is put in the deepest room of it, by storey and not by hop count" do
    create(:quest_step, :speak_to, quest: @quest, position: 1, target_name: "Prince Aurel Durn")
    deepest = open_rooms(Quest::Deadline::GRACE_ROOMS + 1).last

    Quest::Deadline.after_realizing!(deepest)
    prince = @story.characters.find_by(fullname: "Prince Aurel Durn")

    floors = prince.location.parent_location.child_locations

    assert_equal floors.minimum(:z), prince.location.z
  end

  test "the engine writes the person a whole sheet, because the registry refuses half a one" do
    create(:quest_step, :speak_to, quest: @quest, position: 1, target_name: "Prince Aurel Durn",
                                   summary: "Find where they are keeping him.")
    deepest = open_rooms(Quest::Deadline::GRACE_ROOMS + 1).last

    Quest::Deadline.after_realizing!(deepest)
    prince = @story.characters.find_by(fullname: "Prince Aurel Durn")

    Character::Registry::SHEET.each { |field| assert_predicate prince.public_send(field), :present? }
    assert_predicate prince, :stat_block?, "the engine rolls a body like it does for anybody else"
  end

  # --- a thing ---------------------------------------------------------------

  test "a thing target is left lying in the deepest room the party can reach" do
    step = create(:quest_step, :hold_item, quest: @quest, position: 1, target_name: "the cell key")
    deepest = open_rooms(Quest::Deadline::GRACE_ROOMS + 1).last

    Quest::Deadline.after_realizing!(deepest)

    key = Item.in_story(@story).find_by(name: "the cell key")

    assert_not_nil key
    assert_equal deepest, key.location
    assert_equal key, step.reload.target
  end

  # --- where -----------------------------------------------------------------

  test "the anchor is the deepest room by storey, and a tie goes to the furthest out" do
    rooms = open_rooms(Quest::Deadline::GRACE_ROOMS + 1)
    cellar = rooms.last
    place = create(:location, story: @story, name: "The Old Workings", width: 10, depth: 10)
    Location::Interior.lay_out!(place)
    connect!(cellar, Location::Interior.entry_room(place))
    below = place.child_locations.order(:z).first
    below.update!(z: -2)

    create(:quest_step, :reach_location, quest: @quest, position: 1, target_name: "Blackfang Warren")
    Quest::Deadline.after_realizing!(cellar)

    warren = @story.locations.find_by(name: "Blackfang Warren")

    assert_includes Location::Interior.entry_room(warren).exits, below,
                    "z decides, so a cellar is not the street just because both are two hops out"
  end

  test "a room nothing leads to is never the anchor" do
    rooms = open_rooms(Quest::Deadline::GRACE_ROOMS + 1)
    orphan = create(:location, :realized, story: @story, name: "the orphan")

    create(:quest_step, :reach_location, quest: @quest, position: 1, target_name: "Blackfang Warren")
    Quest::Deadline.after_realizing!(rooms.last)

    warren = @story.locations.find_by(name: "Blackfang Warren")

    assert_not_includes Location::Interior.entry_room(warren).exits, orphan
  end

  test "only one thing is placed per realization" do
    create(:quest_step, :reach_location, quest: @quest, position: 1, target_name: "Blackfang Warren")
    create(:quest_step, :speak_to, quest: @quest, position: 2, target_name: "Prince Aurel Durn")
    deepest = open_rooms(Quest::Deadline::GRACE_ROOMS + 1).last

    Quest::Deadline.after_realizing!(deepest)

    assert_not_nil @story.locations.find_by(name: "Blackfang Warren")
    assert_nil @story.characters.find_by(fullname: "Prince Aurel Durn")
  end

  private

  # Realized rooms in a chain out from the gate, so every one of them is
  # reachable and the last is the newest thing the player could stand in.
  def open_rooms(count)
    previous = @story.locations.realized.order(:id).last
    Array.new(count) do |index|
      room = create(:location, :realized, story: @story, name: "opened room #{@story.locations.count + index}")
      connect!(previous, room)
      previous = room
      room
    end
  end

  def connect!(from, to)
    [ [ from, to ], [ to, from ] ].each do |one, other|
      LocationConnection.create!(location: one, connected_location: other,
                                 distance: LocationConnection::DISTANCES.keys.first, travel_method: "walking")
    end
  end
end
