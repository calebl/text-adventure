require "test_helper"

# THE INITIAL SNAPSHOT ANY PLAYTHROUGH USES, and the only thing in the app that
# writes the playthrough layer.
#
# The claims worth pinning are the ones a reading of the class cannot settle:
# what a copy carries, where it lands, and that the guard is per TEMPLATE rather
# than per room -- which is what stops a party that emptied a room finding it
# refurnished the next time they walk in.
#
# Nothing here calls a model. Every row it writes is a copy of a row that
# already exists.
class Item::SnapshotTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @protagonist = create(:character, :protagonist, story: @story, fullname: "Odile Vance")
    @office = create(:location, story: @story, name: "Ward Office 12")
  end

  def playing(location: @office)
    create(:playthrough, story: @story, character: @protagonist, current_location: location)
  end

  # --- what a copy is ------------------------------------------------------

  # EVERY COLUMN BUT WHERE IT IS AND WHOSE IT IS. A column added to `items`
  # later must come along without anybody remembering to add it here -- which is
  # exactly what did not happen to `readable` and `inscription` when they
  # landed, so each player's copy of a seeded note opened blank.
  test "a copy is the same thing, in this game, and knows what it is a copy of" do
    note = create(:item, :lying, :readable, location: @office, name: "folded note")

    copy = playing.items_lying_in(@office).sole

    assert_equal note.attributes.except(*Item::NOT_COPIED), copy.attributes.except(*Item::NOT_COPIED)
    assert_equal note, copy.template
    assert_equal note.inscription, copy.inscription
    assert_predicate copy, :instance?
    assert_predicate note.reload, :template?
  end

  # --- where a copy lands --------------------------------------------------

  test "what is lying in a room is copied lying in that room" do
    create(:item, :lying, location: @office, name: "ward stamp")

    copy = playing.items_lying_in(@office).sole

    assert_predicate copy, :lying?
    assert_equal @office, copy.location
  end

  # THE ONE STATED EXCEPTION. The protagonist is the player, so what the world
  # says they start out holding lands in the PARTY'S hands -- which is a place
  # with no holder, because the party is wherever the playthrough is.
  test "what the protagonist holds is copied into the party's own hands" do
    create(:item, character: @protagonist, location: nil, name: "Ward Office 12 daybook")

    copy = playing.carried.sole

    assert_predicate copy, :carried?
    assert_nil copy.character_id
    assert_nil copy.location_id
  end

  # AND COMPANIONS ARE NOT THE EXCEPTION. `Item.for_character` was never the
  # party's inventory for anybody but the protagonist, so a companion's lantern
  # stays in the companion's hands exactly like any other person's.
  test "what one of the world's own people holds is copied into that person's hands, in this game" do
    rowe = create(:character, story: @story, fullname: "Halkett Rowe", location: @office)
    lantern = create(:item, character: rowe, location: nil, name: "a hooded lantern")

    playthrough = playing
    copy = playthrough.items_held_by(rowe).sole

    assert_predicate copy, :held?
    assert_equal rowe, copy.character
    assert_equal lantern, copy.template
    assert_empty playthrough.carried.by_name("a hooded lantern"), "an NPC's things are not the party's"
    assert_empty playthrough.items_lying_in(@office), "an NPC's things are not takeable off the floor"
  end

  # TWO GAMES, TWO LANTERNS, and the same statement one place over from the
  # floor: what one party talks its way out of somebody's hands is out of that
  # party's world and nobody else's.
  test "two playthroughs each get their own copy of what an NPC is holding" do
    rowe = create(:character, story: @story, fullname: "Halkett Rowe", location: @office)
    create(:item, character: rowe, location: nil, name: "a hooded lantern")

    first = playing
    second = playing

    assert_equal 1, first.items_held_by(rowe).count
    assert_equal 1, second.items_held_by(rowe).count
    assert_not_equal first.items_held_by(rowe).sole, second.items_held_by(rowe).sole
  end

  # A person standing nowhere can never be met, so nothing is copied for them.
  test "nothing is copied for somebody who is not in the room" do
    elsewhere = create(:location, story: @story, name: "The Supply Closet")
    perrin = create(:character, story: @story, fullname: "Perrin Lasco", location: elsewhere)
    create(:item, character: perrin, location: nil, name: "a private index")

    assert_empty playing.items_held_by(perrin)
  end

  # --- the guard is per template -------------------------------------------

  # THE ONE THAT WOULD DUPLICATE A WORLD. "This room is done" would put the
  # stamp back on the floor the moment the party walked back in, once per
  # return trip, for ever.
  test "a room the party has emptied is not refurnished on the way back in" do
    create(:item, :lying, location: @office, name: "ward stamp")
    playthrough = playing
    Playthrough::Turn.new(playthrough).carry!(playthrough.items_lying_in(@office).sole)

    assert_no_difference -> { Item.count } do
      Item::Snapshot.new(playthrough).of_the_room!(@office)
    end
    assert_empty playthrough.items_lying_in(@office)
    assert_equal [ "ward stamp" ], playthrough.carried.pluck(:name)
  end

  # AND THE OTHER DIRECTION: a template written into a room long after the party
  # first stood in it is copied the next time the question is asked. That is
  # what `Item::Registry` does when a room is realized mid-game, and what a
  # person walking in carrying something does.
  test "a template added to a room the party has already been in is copied when they are next there" do
    playthrough = playing
    create(:item, :lying, location: @office, name: "a gas key")

    assert_difference -> { Item.count }, 1 do
      Item::Snapshot.new(playthrough).of_the_room!(@office)
    end
    assert_equal [ "a gas key" ], playthrough.items_lying_in(@office).pluck(:name)
  end

  # An instance with no `template_id` counts for nothing: guessing at the link
  # by name is the one thing every backfill in this app refuses to do, and this
  # is the same rule one class over.
  test "a copy of nothing does not stand in for the copy a template is owed" do
    stamp = create(:item, :lying, location: @office, name: "ward stamp")
    playthrough = playing
    playthrough.items.destroy_all
    create(:item, :carried, playthrough: playthrough, name: "ward stamp")

    Item::Snapshot.new(playthrough).of_the_room!(@office)

    assert_equal [ stamp ], playthrough.items_lying_in(@office).map(&:template)
  end

  test "nothing is copied for a playthrough standing nowhere" do
    create(:item, :lying, location: @office, name: "ward stamp")
    playthrough = create(:playthrough, story: @story, character: @protagonist)

    assert_no_difference -> { Item.count } do
      Item::Snapshot.new(playthrough).of_the_room!(nil)
    end
  end

  # A story whose protagonist nothing has given anything to -- which is every
  # generated world, since `rake game:new` writes no items and `Item::Registry`
  # furnishes rooms and never people.
  test "a story with no starting inventory copies nothing into the party's hands" do
    assert_empty playing.carried
  end
end
