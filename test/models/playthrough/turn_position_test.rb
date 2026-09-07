require "test_helper"

# WHERE A THING IS WHILE A GAME IS BEING PLAYED, which is the one part of slice 4
# that PLAY can move. Everything else about a position is written once by the
# world and asserted where it is written (`Location::PlacementTest`,
# `Item::RegistryTest`, `Character::RegistryTest`); this is the take, the drop,
# the throw through a doorway and the body that lets go of everything.
#
# THE THREE WRITERS ARE CALLED DIRECTLY, on the same terms `Playthrough::Mechanics`
# calls them: they are the statements the loop owns, and a test that went through
# the classifier and the narrator to reach them would be asserting the prose
# rather than the row. `lib/engine_sweep/scripts/things-land-somewhere-in-a-room.yml`
# is the walk that asserts a player typing ordinary lines reaches them at all.
class Playthrough::TurnPositionTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @protagonist = create(:character, story: @story, fullname: "Iri Calder", is_protagonist: true)
    @place = create(:location, :stub, :with_a_footprint, story: @story, name: "The Custom House")
    @here = create(:location, story: @story, parent_location: @place, name: "The Long Room",
                              x: 0, y: 0, z: 0, width: 7, depth: 4)
    @next_door = create(:location, story: @story, parent_location: @place, name: "The Weighing Room",
                                   x: 7, y: 0, z: 0, width: 7, depth: 4)
    @playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
    @turn = Playthrough::Turn.new(@playthrough)
  end

  def lying_here(**overrides)
    create(:item, character: nil, location: @here, playthrough: @playthrough,
                  template: create(:item, character: nil, location: @here), **overrides)
  end

  # --- a take takes it off the floor plan -----------------------------------

  # A THING IN A HAND IS IN NO ROOM, so there is no plane to read a position in.
  # `Item#a_position_needs_a_floor` refuses the alternative, which is what makes
  # forgetting this impossible rather than invisible.
  test "a taken thing loses its position" do
    key = lying_here(x: 3, y: 2)

    @turn.carry!(key)

    assert_predicate key.reload, :carried?
    assert_nil key.position
  end

  # --- a drop gives it a new one --------------------------------------------

  test "a dropped thing lands somewhere inside the room the party is standing in" do
    key = create(:item, :carried, playthrough: @playthrough, name: "brass key")

    @turn.put_down!(key)

    assert_equal @here, key.reload.location
    assert @here.box.contains?(key.position), "#{key.position} is outside #{@here.box}"
  end

  # THE WHOLE ROUND TRIP, which is the path the spec names: off the floor into a
  # hand and back onto the floor, with the record honest at every step.
  test "a thing taken and put down again is placed inside the room once more" do
    key = lying_here(x: 6, y: 3)

    @turn.carry!(key)
    assert_nil key.reload.position

    @turn.put_down!(key)

    assert @here.box.contains?(key.reload.position), "#{key.position} is outside #{@here.box}"
  end

  # A THROW THROUGH A DOORWAY IS THE ONE DROP THAT LANDS SOMEWHERE ELSE, and it
  # needs no special case: `into:` is which floor, and the placement reads the
  # box of whatever floor that is.
  test "a thing put down in the next room is placed in that room's box" do
    key = create(:item, :carried, playthrough: @playthrough, name: "brass key")

    @turn.put_down!(key, into: @next_door)

    assert_equal @next_door, key.reload.location
    assert @next_door.box.contains?(key.position), "#{key.position} is outside #{@next_door.box}"
    assert_not @here.box.contains?(key.position), "it landed in a cell of the room it was thrown out of"
  end

  # THE ORDINARY CASE, and every room in the three checked-in worlds: a room
  # with no box opens no plane, so a drop into one writes no position and a
  # flat world plays exactly as it did before this slice.
  test "a drop into a room with no box leaves the thing unplaced" do
    flat = create(:location, story: @story, name: "The Quay")
    key = create(:item, :carried, playthrough: @playthrough, name: "brass key")

    @turn.put_down!(key, into: flat)

    assert_equal flat, key.reload.location
    assert_nil key.position
  end

  # --- the world's own row never moves --------------------------------------

  # THE CAPTAIN'S RULING OF 2026-09-04, read as a position: the template's cell
  # is the initial snapshot every game starts from, so it must survive one
  # player emptying the room.
  test "taking and dropping a copy leaves the template's own cell alone" do
    template = create(:item, character: nil, location: @here, x: 1, y: 1)
    copy = create(:item, character: nil, location: @here, playthrough: @playthrough,
                         template: template, x: 1, y: 1)

    @turn.carry!(copy)
    @turn.put_down!(copy)

    assert_equal Location::Spot.new(x: 1, y: 1), template.reload.position
  end

  # --- what a body lets go of -----------------------------------------------

  # EACH THING IS ITS OWN ROLL, and that is asserted by RE-DERIVING each cell
  # rather than by checking the three came out different: two of three draws
  # landing in one cell of a 28-cell room is an ordinary coincidence, and a test
  # that failed on it would be a lottery on whoever ran the suite next
  # (`test/factories/location_connections.rb` has the diagnosis).
  test "what a dead body spills is placed on the floor it fell on, each by its own roll" do
    guard = create(:character, story: @story, fullname: "Halkett Rowe", location: @here)
    held = (1..3).map do |n|
      create(:item, character: guard, location: nil, playthrough: @playthrough, name: "guard thing #{n}")
    end

    @turn.spill!(guard)

    held.each do |item|
      assert_equal @here, item.reload.location
      assert @here.box.contains?(item.position), "#{item.name} is #{item.position}, outside #{@here.box}"
      assert_equal Location::Spot.new(**Location::Placement.in_a_game(@here, item, playthrough: @playthrough)),
                   item.position
    end
  end
end
