require "test_helper"

# HOW MUCH IS LEFT OF ONE BODY IN ONE GAME.
#
# The captain's ruling of 2026-09-04 applied to people: the world owns the stat
# block and the playthrough owns the condition. What these pin is the split
# itself -- one game's wound is invisible to another -- and the two rules the
# table stands on: an absent row means unhurt, and zero means dead.
class Playthrough::VitalsTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @room = create(:location, story: @story)
    @vance = create(:character, :protagonist, story: @story, fullname: "Odile Vance",
                                              level: 1, hit_die: 6)
    @rowe = create(:character, story: @story, fullname: "Halkett Rowe", location: @room,
                              level: 1, hit_die: 8)
    @game = create(:playthrough, story: @story, character: @vance, current_location: @room)
  end

  # --- the record ------------------------------------------------------------

  test "a body starts at the maximum its stat block allows" do
    row = Playthrough::Vitals.instantiate!(@game, @vance)

    assert_equal @vance.max_hp, row.hp_current
    assert_equal 6, row.hp_current
  end

  test "instantiating twice is one row" do
    first = Playthrough::Vitals.instantiate!(@game, @rowe)
    second = Playthrough::Vitals.instantiate!(@game, @rowe)

    assert_equal first.id, second.id
    assert_equal 1, Playthrough::Vitals.where(playthrough: @game, character: @rowe).count
  end

  # A hurt body that is instantiated again is NOT put back to full: the guard is
  # `find_or_create_by!`, so the second call reads rather than writes. It is the
  # rule the snapshot at the top of every turn depends on entirely.
  test "instantiating a body that has already been hurt reads it rather than healing it" do
    Playthrough::Turn.new(@game).harm!(@rowe, 3)

    assert_equal 5, Playthrough::Vitals.instantiate!(@game, @rowe).hp_current
  end

  test "somebody with no stat block gets no row at all" do
    nobody = create(:character, :without_a_stat_block, story: @story)

    assert_nil Playthrough::Vitals.instantiate!(@game, nobody)
    assert_equal 0, Playthrough::Vitals.where(character: nobody).count
  end

  test "one body cannot have two rows in one game" do
    Playthrough::Vitals.instantiate!(@game, @rowe)
    duplicate = Playthrough::Vitals.new(playthrough: @game, character: @rowe, hp_current: 4)

    assert_not duplicate.valid?
  end

  test "a body cannot hold more than its stat block allows" do
    row = Playthrough::Vitals.new(playthrough: @game, character: @vance, hp_current: 7)

    assert_not row.valid?
    assert_match(/past the 6/, row.errors.full_messages.join)
  end

  test "a body cannot go below zero" do
    row = Playthrough::Vitals.new(playthrough: @game, character: @vance, hp_current: -1)

    assert_not row.valid?
  end

  test "a condition for somebody in another story is refused" do
    stranger = create(:character, story: create(:story))
    row = Playthrough::Vitals.new(playthrough: @game, character: stranger, hp_current: 1)

    assert_not row.valid?
    assert_match(/must belong to the playthrough's story/, row.errors.full_messages.join)
  end

  test "a condition is destroyed with the game it belongs to" do
    Playthrough::Vitals.instantiate!(@game, @rowe)
    @game.destroy!

    assert_equal 0, Playthrough::Vitals.where(playthrough_id: @game.id).count
  end

  test "a condition is destroyed with the person it is about" do
    Playthrough::Vitals.instantiate!(@game, @rowe)

    assert_difference -> { Playthrough::Vitals.count }, -1 do
      @rowe.destroy!
    end
  end

  # --- the condition ---------------------------------------------------------

  # Somebody in another room, because the party's own room is snapshotted the
  # moment the playthrough is created -- which is the point of the snapshot and
  # would hide the rule this is about.
  test "an absent row means unhurt" do
    elsewhere = create(:character, story: @story, location: create(:location, story: @story),
                                   level: 1, hit_die: 8)
    condition = @game.vitals_for(elsewhere)

    assert_equal 0, Playthrough::Vitals.where(playthrough: @game, character: elsewhere).count
    assert_equal 8, condition.hp
    assert condition.unhurt?
    assert_equal "unhurt", condition.in_words
  end

  test "a condition says nothing at all about somebody with no stat block" do
    assert_nil @game.vitals_for(create(:character, :without_a_stat_block, story: @story))
    assert_nil @game.vitals_for(nil)
  end

  # One threshold and not a table of them, so the boundary is worth pinning:
  # half the maximum or worse is "badly hurt", and one more than half is not.
  test "badly hurt is half the maximum or worse" do
    turn = Playthrough::Turn.new(@game)

    assert_equal "hurt (5 of 8)", turn.harm!(@rowe, 3).in_words
    assert_equal "badly hurt (4 of 8)", turn.harm!(@rowe, 1).in_words
    assert_equal "badly hurt (3 of 8)", turn.harm!(@rowe, 1).in_words
  end

  test "a condition reads as a sentence for a prompt" do
    assert_equal "Halkett Rowe is unhurt.", @game.vitals_for(@rowe).to_s
    assert_equal "Halkett Rowe is badly hurt (1 of 8).",
                 Playthrough::Turn.new(@game).harm!(@rowe, 7) && @game.vitals_for(@rowe).to_s
  end

  test "zero is dead and says so" do
    condition = Playthrough::Turn.new(@game).harm!(@rowe, 8)

    assert condition.dead?
    assert_equal "dead", condition.in_words
  end

  # --- the layer split -------------------------------------------------------

  # THE WHOLE RULING IN ONE TEST. Two games of one world, one body hurt in one
  # of them. With a column on `characters` this could not be true.
  test "one game's wound is invisible to another game of the same world" do
    other = create(:playthrough, story: @story, character: @vance, current_location: @room)

    Playthrough::Turn.new(@game).harm!(@rowe, 5)

    assert_equal 3, @game.vitals_for(@rowe).hp
    assert_equal 8, other.vitals_for(@rowe).hp
  end

  test "hurting somebody does not touch the world's stat block" do
    Playthrough::Turn.new(@game).harm!(@rowe, 5)

    assert_equal [ 1, 8 ], [ @rowe.reload.level, @rowe.hit_die ]
  end
end
