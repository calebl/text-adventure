require "test_helper"

# THE CAPTAIN'S FIVE PROPERTIES OF "PLAYABLE IN A REASONABLE WAY", four of them,
# as things a command asserts. His fifth -- the world has somebody in it to talk
# to -- is `ta-room-people-count` and is not here.
#
#   P1  the goal exists as a row before the player can run out of frontier
#   P2  the frontier keeps pointing at the goal
#   P3  every step is reachable from the opening room
#   P4  the ending is written
#
# THE WORLD STORY 7 ACTUALLY WAS is the case at the bottom: a story whose whole
# premise turns on a prince who is in no row at all. The doctor called it
# HEALTHY. These are what would have named it.
class Story::DoctorArcTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @gate = create(:location, :realized, story: @story, name: "Iron Gate Chamber")
    @maw = create(:location, :realized, story: @story, name: "obsidian maw")
    connect!(@gate, @maw)
    @quest = create(:quest, story: @story, title: "The Long Way Down")
    create(:quest_outcome, :default, quest: @quest, name: "rescued")
  end

  def codes = Story::Doctor.new(@story.reload).findings.map(&:code)

  # --- a world with no arc is untouched --------------------------------------

  test "a story with no arc gets no arc findings at all" do
    @quest.destroy

    assert_empty codes.grep(/quest|frontier|conclusion|progress/)
  end

  # --- P4: the ending is written ---------------------------------------------

  test "an arc with no outcome is reported, and so is the story with no conclusion" do
    @quest.outcomes.destroy_all
    bound_step(@maw)

    assert_includes codes, :quest_without_an_outcome
    assert_includes codes, :story_without_a_conclusion
  end

  test "two defaults are reported, because which one the world was born with becomes arbitrary" do
    bound_step(@maw)
    create(:quest_outcome, :default, quest: @quest, name: "too-late", summary: "Three days late.")

    assert_includes codes, :quest_with_two_default_outcomes
  end

  # --- an ending nothing can select ------------------------------------------

  test "a non-default ending with no rule is an ending no game can reach" do
    bound_step(@maw)
    create(:quest_outcome, quest: @quest, name: "too-late", summary: "Three days late.")

    assert_includes codes, :outcome_nothing_can_reach
  end

  test "an ending with a rule is reachable, and the default needs none" do
    bound_step(@maw)
    create(:quest_outcome, :out_of_order, quest: @quest, name: "too-late", summary: "Three days late.")

    assert_not_includes codes, :outcome_nothing_can_reach
  end

  # --- the event stream, which needs no arc at all ---------------------------

  test "a scheduled event whose hour has passed with nothing fired is reported" do
    create(:world_event, :scheduled, story: @story, scheduled_for: @story.start_time + 5.minutes)
    create(:scene, story: @story, location: @gate, story_timestamp: @story.start_time + 1.hour)

    assert_includes codes, :scheduled_event_never_fired
  end

  test "an hour this story has not reached is not a defect" do
    create(:world_event, :scheduled, story: @story, scheduled_for: @story.start_time + 8.hours)

    assert_not_includes codes, :scheduled_event_never_fired
  end

  test "a row stamped as fired that was never due is reported" do
    event = create(:world_event, :scheduled, story: @story)
    event.update_columns(scheduled_for: nil, fired_at: @story.start_time)

    assert_includes codes, :fired_event_without_a_schedule
  end

  test "the event stream is asked about in a world with no arc at all" do
    @quest.destroy
    create(:world_event, :scheduled, story: @story, scheduled_for: @story.start_time + 5.minutes)
    create(:scene, story: @story, location: @gate, story_timestamp: @story.start_time + 1.hour)

    assert_includes codes, :scheduled_event_never_fired
  end

  # --- P1: the goal exists as a row ------------------------------------------

  test "an unbound step is a warning, and a whole arc of them is fatal" do
    create(:quest_step, :reach_location, quest: @quest, position: 1, target_name: "Blackfang Warren")

    assert_includes codes, :quest_step_unbound
    assert_includes codes, :story_cannot_progress
    assert_not_predicate Story::Doctor.new(@story.reload), :playable?
  end

  # A young generated world is SUPPOSED to be unbound -- the arc states what the
  # world must contain and the registries grow it as the player explores.
  test "a young generated world is warned about and never called unplayable" do
    @quest.update!(origin: "generated")
    create(:quest_step, :reach_location, quest: @quest, position: 1, target_name: "Blackfang Warren")

    assert_includes codes, :quest_step_unbound
    assert_not_includes codes, :story_cannot_progress
    assert_predicate Story::Doctor.new(@story.reload), :playable?
  end

  test "a generated world past the deadline with nothing bound is one that stopped growing" do
    @quest.update!(origin: "generated")
    create(:quest_step, :reach_location, quest: @quest, position: 1, target_name: "Blackfang Warren")
    (Quest::Deadline::GRACE_ROOMS + 1).times { |n| create(:location, :realized, story: @story, name: "room #{n}") }

    assert_includes codes, :story_cannot_progress
  end

  test "a bound target whose row went away is reported and can be safely unbound" do
    step = bound_step(@maw)
    @maw.destroy

    finding = Story::Doctor.new(@story.reload).findings.detect { |one| one.code == :quest_target_missing }

    assert_not_nil finding
    assert_equal :safe, finding.remedy
    assert_equal step, finding.subject
  end

  # A `:safe` remedy is a promise `Story::Repair` keeps, so the finding above has
  # to be one it actually handles -- otherwise the doctor offers a fix nothing
  # applies.
  test "the missing target is repaired by putting the beat back to waiting" do
    step = bound_step(@maw)
    @maw.destroy

    repair = Story::Repair.new(@story.reload)

    assert_equal [ :quest_target_missing ], repair.plan.map(&:code)
    repair.apply!

    assert_predicate step.reload, :unbound?
    assert_equal "obsidian maw", step.target_name
  end

  # --- P3: the arc can complete ----------------------------------------------

  test "a bound target no path leads to is fatal" do
    stranded = create(:location, :realized, story: @story, name: "the far shore")
    bound_step(stranded)

    assert_includes codes, :quest_target_unreachable
    assert_not_predicate Story::Doctor.new(@story.reload), :playable?
  end

  test "a target inside a laid-out place is asked about through its entry room" do
    warren = create(:location, story: @story, name: "Blackfang Warren", width: 12, depth: 10)
    Location::Interior.lay_out!(warren)
    connect!(@maw, Location::Interior.entry_room(warren))
    bound_step(warren)

    assert_not_includes codes, :quest_target_unreachable
  end

  test "a person standing nowhere is not unreachable" do
    step = create(:quest_step, :speak_to, quest: @quest, position: 1, target_name: "Perrin Lasco")
    step.bind!(create(:character, story: @story, fullname: "Perrin Lasco"), at: @story.start_time)

    assert_not_includes codes, :quest_target_unreachable
  end

  # --- P2: the frontier keeps pointing at the goal ---------------------------
  #
  # STOREYS AND NOT HOPS, which is the captain's Q5: on his own world the bottom
  # of the dungeon and the way out of it were both two hops from the opening
  # room, and a check built on that tie would have said nothing.

  test "a goal deeper than every unexplored room is reported" do
    cell = deep_room("the dry cell", -2)
    create(:location, story: @story, name: "the surface", width: 4, depth: 4)
    bound_step(cell)

    assert_includes codes, :frontier_turned_away_from_the_goal
  end

  test "an unexplored room level with the goal or below it is not reported" do
    cell = deep_room("the dry cell", -2)
    deep_room("the flooded gallery", -3, visited: false)
    bound_step(cell)

    assert_not_includes codes, :frontier_turned_away_from_the_goal
  end

  test "a flat world says nothing about direction, because it has none to say" do
    tunnel = create(:location, story: @story, name: "Blackfang Tunnel")
    connect!(@maw, tunnel)
    bound_step(tunnel)

    assert_not_includes codes, :frontier_turned_away_from_the_goal
  end

  # --- the world the captain actually generated ------------------------------

  test "a story whose whole premise is in prose and in no row is no longer healthy" do
    @quest.update!(origin: "generated")
    create(:quest_step, :speak_to, quest: @quest, position: 1, target_name: "Prince Aurel Durn",
                                   summary: "Find where the Blackfang are keeping him.")

    doctor = Story::Doctor.new(@story.reload)

    assert_not_predicate doctor, :healthy?
    assert_includes doctor.findings.map(&:message).join, "Prince Aurel Durn"
  end

  private

  def bound_step(record, position: 1)
    kind = record.is_a?(Character) ? :speak_to : :reach_location
    name = record.is_a?(Character) ? record.fullname : record.name
    step = create(:quest_step, kind, quest: @quest, position: position, target_name: name)
    step.bind!(record, at: @story.start_time)
    step
  end

  # A room on a storey, which needs a parent to be read in the plane of --
  # coordinates are local (`Location::Box`), so a `z` on a row with no parent is
  # a number measured against nothing.
  def deep_room(name, storey, visited: true)
    place = create(:location, story: @story, name: "#{name} -- the place", width: 8, depth: 8)
    room = create(:location, :realized, story: @story, name: name, parent_location: place,
                                        x: 0, y: 0, z: storey, width: 4, depth: 4)
    connect!(@maw, room)
    room.update!(last_protagonist_visit: @story.start_time) if visited
    room
  end

  def connect!(from, to)
    [ [ from, to ], [ to, from ] ].each do |one, other|
      LocationConnection.create!(location: one, connected_location: other,
                                 distance: LocationConnection::DISTANCES.keys.first, travel_method: "walking")
    end
  end
end
