require "test_helper"

# THE ONE WRITER OF A POSITION, and what this asserts is the half
# `Location::SpotTest` cannot: WHICH generator the cell comes out of, and
# therefore whether the same thing is in the same place next week. See
# `Location::Placement`.
class Location::PlacementTest < ActiveSupport::TestCase
  setup do
    @story = create(:story)
    @place = create(:location, :stub, :with_a_footprint, story: @story, name: "The Rusted Anchor")
    @room = create(:location, story: @story, parent_location: @place, name: "The Taproom",
                              x: 0, y: 0, z: 0, width: 7, depth: 8)
    @flat = create(:location, :realized, story: @story, name: "The Harbour Road")
  end

  def thing(location: @room)
    create(:item, character: nil, location: location)
  end

  # --- inside the room, always ----------------------------------------------

  test "a world placement is a cell of the room's own box" do
    placed = Location::Placement.in_the_world(@room, thing)

    assert @room.box.contains?(Location::Spot.new(**placed)), "#{placed} is outside #{@room.box}"
  end

  test "a game placement is a cell of the room's own box" do
    game = create(:playthrough, story: @story)
    placed = Location::Placement.in_a_game(@room, thing, playthrough: game)

    assert @room.box.contains?(Location::Spot.new(**placed)), "#{placed} is outside #{@room.box}"
  end

  # A ROOM AWAY FROM THE ORIGIN, because a placement that rolled `0...width`
  # instead of `x...x + width` would pass every assertion above on the taproom
  # and put everything in the back room's neighbour.
  test "a room that does not start at the origin is placed in its own cells" do
    back = create(:location, story: @story, parent_location: @place, name: "The Back Room",
                             x: 7, y: 0, z: 0, width: 5, depth: 8)

    20.times do
      placed = Location::Placement.in_the_world(back, thing(location: back))

      assert_operator placed[:x], :>=, 7
      assert_operator placed[:x], :<, 12
    end
  end

  # --- nowhere to be --------------------------------------------------------

  # THE ORDINARY CASE, and the whole reason the columns are nullable: a room
  # with no box opens no plane, so there is no cell to pick.
  test "a room with no box places nothing" do
    assert_equal Location::Placement.unplaced, Location::Placement.in_the_world(@flat, thing(location: @flat))
  end

  test "no room at all places nothing" do
    assert_equal Location::Placement.unplaced, Location::Placement.in_the_world(nil, thing)
  end

  test "unplaced is both columns and not one" do
    assert_equal %i[x y].sort, Location::Placement.unplaced.keys.sort
    assert_equal [ nil, nil ], Location::Placement.unplaced.values
  end

  # --- what a placement is keyed on -----------------------------------------

  # THE WORLD LAYER IS RE-DERIVABLE FOR EVER, which is why its seed carries the
  # row and nothing else: the same chair put in the same room next week is in
  # the same corner of it. It is also what makes `Character::Registry`'s
  # re-admission of somebody already standing here a no-op rather than a shuffle.
  test "the same row in the same room lands in the same cell every time" do
    item = thing

    assert_equal Location::Placement.in_the_world(@room, item),
                 Location::Placement.in_the_world(@room, item)
  end

  # TWO THINGS ARE TWO ROLLS. Without the row's id on the sequence axis a room's
  # whole contents would stack in one cell.
  test "two rows in one room are two different draws" do
    cells = 12.times.map { Location::Placement.in_the_world(@room, thing) }

    assert_operator cells.uniq.size, :>, 1
  end

  # AN ITEM #7 AND A PERSON #7 ARE DIFFERENT DICE, which is what the two `Roll`
  # kinds buy: ids collide freely across tables, so one axis could not hold both.
  test "an item and a character are placed on their own axes" do
    item = thing
    person = create(:character, story: @story, location: @room)

    assert_not_equal Roll::ITEM_POSITION, Roll::CHARACTER_POSITION
    assert_equal spot_from(Roll::ITEM_POSITION, item.id), Location::Placement.in_the_world(@room, item)
    assert_equal spot_from(Roll::CHARACTER_POSITION, person.id), Location::Placement.in_the_world(@room, person)
  end

  # AND AN ID ON THE WRONG AXIS IS A DIFFERENT CELL, which is the half the test
  # above cannot show on two rows that happen to have different ids: `items.id`
  # and `characters.id` collide freely, so what keeps a chair #7 and a clerk #7
  # apart has to be the kind and nothing else.
  test "one id on the two axes is two different cells" do
    item = thing

    assert_not_equal spot_from(Roll::CHARACTER_POSITION, item.id),
                     Location::Placement.in_the_world(@room, item)
  end

  def spot_from(kind, sequence)
    Location::Spot.inside(@room.box,
                          rng: Roll.generator(story: @story.id, sequence: sequence, kind: kind)).to_h
  end

  # A GAME'S OWN DIE. The world's answer and one game's answer for the same row
  # are drawn from different seeds, so a drop does not put a thing back where
  # the world laid it.
  test "a game places the same row differently from the world" do
    item = thing
    game = create(:playthrough, story: @story)

    assert_not_equal Location::Placement.in_the_world(@room, item),
                     Location::Placement.in_a_game(@room, item, playthrough: game)
  end

  # AND TWO GAMES ARE TWO DICE, which is the layer split read as a roll: what
  # one player did to their copy of the floor is not what the next player finds.
  test "two games place one row from two seeds" do
    item = thing
    one = create(:playthrough, story: @story)
    other = create(:playthrough, story: @story)

    assert_not_equal Location::Placement.in_a_game(@room, item, playthrough: one),
                     Location::Placement.in_a_game(@room, item, playthrough: other)
  end

  # THE STORY'S CLOCK IS IN A GAME'S SEED, so setting a thing down later in the
  # story is setting it down somewhere else. Story time, never the wall clock --
  # `Roll`'s rule.
  test "a later moment in one game places the same row somewhere else" do
    item = thing
    game = create(:playthrough, story: @story)
    early = Location::Placement.in_a_game(@room, item, playthrough: game)

    later = create(:scene, story: @story, location: @room, story_timestamp: game.story_now + 3.hours)
    game.update!(current_scene: later)

    assert_not_equal early, Location::Placement.in_a_game(@room, item, playthrough: game)
  end

  # --- what it refuses ------------------------------------------------------

  # A THIRD TABLE GETS A THIRD KIND. Kind `0` is the axis every roll thrown
  # before kinds existed shares, so falling back to it would seed a new table's
  # positions identically to a stat block's.
  test "a row from a table with no axis is refused rather than placed on kind zero" do
    error = assert_raises(ArgumentError) { Location::Placement.in_the_world(@room, @story) }

    assert_match(/no position axis/, error.message)
  end
end
