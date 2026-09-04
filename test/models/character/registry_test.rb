require "test_helper"

# The people half of the noun registry. One rule matters more than the rest and
# it is the Tide Post defect written down: a proposal never moves somebody who
# is already somewhere.
class Character::RegistryTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @here = create(:location, story: @story, name: "The Causeway Court")
    @there = create(:location, story: @story, name: "The Tide Post")
  end

  def registry(location = @here) = Character::Registry.new(location)

  # --- placing --------------------------------------------------------------

  test "somebody nowhere is placed, and the room's cast is what comes back" do
    brace = create(:character, story: @story, fullname: "Ammon Brace")

    present = registry.admit!([ brace ])

    assert_equal @here, brace.reload.location
    assert_equal [ brace ], present
  end

  test "a proposal may name somebody by fullname or by nickname" do
    neb = create(:character, story: @story, fullname: "Neb Halloran", nickname: "Neb")

    registry.admit!([ "neb" ])

    assert_equal @here, neb.reload.location
  end

  test "the cast that comes back is read out of the records, not out of the proposal" do
    standing = create(:character, story: @story, fullname: "Ammon Brace", location: @here)

    present = registry.admit!([])

    assert_equal [ standing ], present
  end

  # --- refusing -------------------------------------------------------------

  # THE DEFECT THIS CLASS EXISTS FOR. Arriving at The Tide Post recorded the
  # protagonist alone on all three runs checked, in a world whose premise is
  # that Neb Halloran is chained to that post -- because the cast was
  # regenerated from scratch every time. A proposal is evidence about a room and
  # never authority over a person.
  test "a character who is already somewhere is not moved" do
    neb = create(:character, story: @story, fullname: "Neb Halloran", location: @there)

    present = registry.admit!([ neb ])

    assert_equal @there, neb.reload.location, "the proposal moved somebody it should only have proposed"
    assert_equal [], present
  end

  test "a name nobody in this story answers to is refused, not created" do
    assert_no_difference -> { Character.count } do
      assert_equal [], registry.admit!([ "Somebody Who Does Not Exist" ])
    end
  end

  test "a character of another story is not placed here" do
    stranger = create(:character, story: create(:story), fullname: "Neb Halloran")

    registry.admit!([ stranger ])

    assert_predicate stranger.reload, :nowhere?
  end

  test "a room already at its cap takes nobody else" do
    Character::Registry::MAX_PER_ROOM.times { create(:character, story: @story, location: @here) }
    late = create(:character, story: @story, fullname: "One Too Many")

    assert_equal 0, registry.room_for_people
    registry.admit!([ late ])

    assert_predicate late.reload, :nowhere?
  end

  # The cap is read back from the records on every candidate rather than counted
  # down from a budget, exactly as `Item::Registry`'s two are -- rows are
  # written as the loop goes.
  test "the cap counts the people written by this very call" do
    over = (Character::Registry::MAX_PER_ROOM + 2).times.map { create(:character, story: @story) }

    present = registry.admit!(over)

    assert_equal Character::Registry::MAX_PER_ROOM, present.size
    assert_equal Character::Registry::MAX_PER_ROOM, Character.present_in(@here).count
  end

  # Placing somebody who is already standing here is a no-op rather than a
  # refusal, so re-proposing a room's own cast does not spend its allowance.
  test "somebody already in this room is not counted against the cap again" do
    standing = create(:character, story: @story, location: @here)

    registry.admit!([ standing, standing ])

    assert_equal Character::Registry::MAX_PER_ROOM - 1, registry.room_for_people
  end

  test "a refusal never raises and never loses the rest of the proposal" do
    neb = create(:character, story: @story, fullname: "Neb Halloran", location: @there)
    brace = create(:character, story: @story, fullname: "Ammon Brace")

    present = registry.admit!([ neb, "nobody of that name", brace ])

    assert_equal [ brace ], present
    assert_equal @there, neb.reload.location
  end
end
