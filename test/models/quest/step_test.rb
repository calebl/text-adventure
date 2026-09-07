require "test_helper"

# THE TWO STATES A BEAT HAS, and the rules that keep them honest.
#
# UNBOUND is a name the world has not grown yet; BOUND is a row. What these pin
# is that a step cannot take the wrong kind of row, that a place resolves to the
# room a party actually stands in, and that binding happens once.
class Quest::StepTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @quest = create(:quest, story: @story)
    @at = @story.start_time
  end

  # --- what a step may be ----------------------------------------------------

  test "a trigger outside the fixed table of four is refused" do
    assert_not build(:quest_step, quest: @quest, trigger_kind: "cast_a_spell").valid?
  end

  test "time_passed needs minutes and refuses a target" do
    assert_not build(:quest_step, quest: @quest, trigger_kind: "time_passed", minutes: nil).valid?
    assert_not build(:quest_step, :reach_location, quest: @quest, minutes: 10).valid?
  end

  test "the other three need a name to wait for" do
    assert_not build(:quest_step, :reach_location, quest: @quest, target_name: nil).valid?
  end

  test "two beats cannot share a position" do
    create(:quest_step, quest: @quest, position: 1)

    assert_not build(:quest_step, quest: @quest, position: 1).valid?
  end

  # --- binding ---------------------------------------------------------------

  test "a step takes a row of its own kind under the natural key" do
    step = create(:quest_step, :reach_location, quest: @quest, target_name: "Blackfang Warren")
    warren = create(:location, story: @story, name: "the Blackfang Warren")

    assert step.takes?(warren)
    assert_not step.takes?(create(:character, story: @story, fullname: "Blackfang Warren"))
  end

  test "binding writes the row and the moment, and never happens twice" do
    step = create(:quest_step, :reach_location, quest: @quest, target_name: "Blackfang Warren")
    first = create(:location, story: @story, name: "Blackfang Warren")
    second = create(:location, story: @story, name: "Blackfang Warren II")

    step.bind!(first, at: @at)

    assert_equal first, step.reload.target
    assert_equal @at, step.bound_at

    step.bind!(second, at: @at + 1.hour)

    assert_equal first, step.reload.target
    assert_not step.takes?(second)
  end

  test "a bound step is never taken again and an unbound one is not reached" do
    step = create(:quest_step, :reach_location, quest: @quest)
    room = create(:location, story: @story, name: step.target_name)

    assert_predicate step, :unbound?
    step.bind!(room, at: @at)

    assert_predicate step, :bound?
    assert_not step.takes?(room)
  end

  test "a row of the wrong class cannot be written to a target at all" do
    step = build(:quest_step, :reach_location, quest: @quest,
                              target: create(:character, story: @story))

    assert_not step.valid?
    assert_includes step.errors.full_messages.join, "must be a Location"
  end

  test "unbinding forgets the row and keeps the name the arc is waiting for" do
    step = create(:quest_step, :reach_location, quest: @quest, target_name: "Blackfang Warren")
    step.bind!(create(:location, story: @story, name: "Blackfang Warren"), at: @at)

    step.unbind!

    assert_predicate step.reload, :unbound?
    assert_equal "Blackfang Warren", step.target_name
  end

  # --- a place is bound as the place and read as the room --------------------
  #
  # The captain's Call 5 of 2026-09-07: a laid-out place is never an endpoint.
  # A step bound to a container would name somewhere nobody ever stands, so the
  # resolution happens at READ time and survives the layout landing afterwards.

  test "a place with no inside yet reads as itself" do
    step = create(:quest_step, :reach_location, quest: @quest, target_name: "Blackfang Warren")
    warren = create(:location, story: @story, name: "Blackfang Warren")
    step.bind!(warren, at: @at)

    assert_equal warren, step.target_room
  end

  test "a place laid out after binding reads as its entry room" do
    step = create(:quest_step, :reach_location, quest: @quest, target_name: "Blackfang Warren")
    warren = create(:location, story: @story, name: "Blackfang Warren", width: 12, depth: 10)
    step.bind!(warren, at: @at)

    Location::Interior.lay_out!(warren)

    entry = Location::Interior.entry_room(warren.reload)

    assert_equal entry, step.reload.target_room
    assert_not_equal warren, step.target_room
  end

  test "a step that is not about a place has no room" do
    step = create(:quest_step, :speak_to, quest: @quest)

    assert_nil step.target_room
  end
end
