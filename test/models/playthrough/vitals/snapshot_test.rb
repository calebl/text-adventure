require "test_helper"

# WHEN A GAME FIRST STANDS IN FRONT OF SOMEBODY, it takes its own copy of how
# much is left of them -- the people half of `Item::Snapshot`, taken at the same
# moments through `Playthrough::Snapshot`.
#
# The rule these pin is the seam: neither half may be taken without the other,
# because a room whose things a game has copied and whose people it has not is a
# silent inconsistency nothing would report.
class Playthrough::Vitals::SnapshotTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @office = create(:location, story: @story, name: "Ward Office 12")
    @closet = create(:location, story: @story, name: "The Supply Closet")
    @vance = create(:character, :protagonist, story: @story, level: 1, hit_die: 6)
    @rowe = create(:character, story: @story, fullname: "Halkett Rowe", location: @office,
                              level: 1, hit_die: 8)
    @lasco = create(:character, story: @story, fullname: "Perrin Lasco", location: @closet,
                               level: 1, hit_die: 6)
  end

  def game
    @game ||= create(:playthrough, story: @story, character: @vance, current_location: @office)
  end

  test "a new playthrough starts with a condition for the party and for the room it opens in" do
    assert_equal [ @vance, @rowe ].map(&:id).sort, game.vitals.map(&:character_id).sort
  end

  test "nobody in another room is copied until the party is standing in front of them" do
    assert_not_includes game.vitals.map(&:character_id), @lasco.id

    Playthrough::Vitals::Snapshot.new(game).of_the_room!(@closet)

    assert_includes game.reload.vitals.map(&:character_id), @lasco.id
  end

  test "taking the snapshot twice writes one row" do
    snapshot = Playthrough::Vitals::Snapshot.new(game)
    snapshot.of_the_room!(@office)
    snapshot.of_the_room!(@office)

    assert_equal 1, game.vitals.where(character: @rowe).count
  end

  # THE RULE THE GUARD EXISTS FOR: a second visit must not put a hurt body back
  # to full. `find_or_create_by!` reads rather than writes, which is what makes
  # the snapshot safe at the top of every turn.
  test "walking back into a room does not heal anybody in it" do
    Playthrough::Turn.new(game).harm!(@rowe, 5)

    Playthrough::Vitals::Snapshot.new(game).of_the_room!(@office)

    assert_equal 3, game.vitals_for(@rowe).hp
  end

  test "nobody is copied for somebody who has no stat block" do
    nobody = create(:character, :without_a_stat_block, story: @story, location: @closet)

    Playthrough::Vitals::Snapshot.new(game).of_the_room!(@closet)

    assert_not_includes game.reload.vitals.map(&:character_id), nobody.id
  end

  test "a room nobody is standing in is a no-op, and so is nowhere" do
    empty = create(:location, story: @story)

    assert_empty Playthrough::Vitals::Snapshot.new(game).of_the_room!(empty)
    assert_empty Playthrough::Vitals::Snapshot.new(game).of_the_room!(nil)
  end

  # THE SEAM. Five call sites take the snapshot and each one has to take BOTH
  # halves; `Playthrough::Snapshot` is what makes that one statement rather than
  # two, and this is the assertion that it really does both.
  test "the one seam copies the things in a room and the people in it together" do
    made = Playthrough::Snapshot.new(game).of_the_room!(@closet)

    assert_equal %i[items vitals].sort, made.keys.sort
    assert_includes made[:vitals].map(&:character_id), @lasco.id
  end

  # AND THAT THE TURN LOOP GOES THROUGH IT. A turn that copied a room's items
  # and not its people would leave a game reading somebody's condition off the
  # world rather than off its own row.
  test "the top of a turn takes both halves" do
    game.update!(current_location: @closet)

    Playthrough::Mechanics.new(game, model: false).run("look")

    assert_includes game.reload.vitals.map(&:character_id), @lasco.id
  end
end
