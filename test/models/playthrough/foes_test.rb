require "test_helper"

# WHO IS FIGHTING THIS PARTY, HERE, IN THIS GAME. `Playthrough#foes_in` is the
# one reader of it, and what it is for is the join: the WORLD says who is
# hostile (`characters.hostile`) and a GAME says who is still standing
# (`playthrough_vitals`). Either half read alone is the wrong answer, and this
# is the test that says so.
#
# Nothing fights yet. What is asserted here is the reader's shape -- so the
# slice that resolves a fight has one query to trust rather than four copies of
# it to keep in step.
class Playthrough::FoesTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @room = create(:location, story: @story, name: "The Bell Chamber")
    @elsewhere = create(:location, story: @story, name: "The Stair")
    @protagonist = create(:character, :protagonist, story: @story)
    @game = create(:playthrough, story: @story, character: @protagonist, current_location: @room)

    @monster = create(:character, :monster, story: @story, location: @room, fullname: "Marek Sollen")
    @bystander = create(:character, story: @story, location: @room, fullname: "Grenn Ollivar")
  end

  test "a foe is somebody hostile, present, and alive in this game" do
    assert_equal [ @monster ], @game.foes_in(@room)
  end

  test "somebody who is merely standing here is not a foe" do
    assert_includes Character.present_in(@room), @bystander
    assert_not_includes @game.foes_in(@room), @bystander
  end

  test "a foe in another room is not a foe here" do
    assert_equal [], @game.foes_in(@elsewhere)
  end

  test "nowhere has no foes in it" do
    assert_equal [], @game.foes_in(nil)
  end

  # THE HALF A WORLD-LEVEL SCOPE CANNOT ANSWER. `Character.hostile` still holds
  # him; this game has taken his last hit point, so this game has no foe here.
  test "a foe this game has killed is not a foe in this game" do
    Playthrough::Turn.new(@game).harm!(@monster, @monster.max_hp)

    assert_predicate @game.vitals_for(@monster), :dead?
    assert_equal [], @game.foes_in(@room)
    assert_includes Character.present_in(@room).hostile, @monster, "the world still says what he is"
  end

  # AND THE OTHER GAME IS UNTOUCHED, which is the whole reason the reader is on
  # `Playthrough` rather than on `Location`.
  test "one game's dead foe is another game's live one" do
    other = create(:playthrough, story: @story, character: @protagonist, current_location: @room)
    Playthrough::Turn.new(@game).harm!(@monster, @monster.max_hp)

    assert_equal [], @game.foes_in(@room)
    assert_equal [ @monster ], other.foes_in(@room)
  end

  test "a wounded foe is still a foe" do
    Playthrough::Turn.new(@game).harm!(@monster, 1)

    assert_equal [ @monster ], @game.foes_in(@room)
  end

  # `Character.present_in` is `.order(:id)` *"so two people in one room are
  # offered in a stable order"*, and a fight has to be able to say who acts when
  # without inventing a second ordering.
  test "foes come out in id order, like everything else in a room" do
    second = create(:character, :monster, story: @story, location: @room, fullname: "Ada Threnn")

    assert_equal [ @monster.id, second.id ].sort, @game.foes_in(@room).map(&:id)
    assert_equal @game.foes_in(@room).map(&:id).sort, @game.foes_in(@room).map(&:id)
  end

  # A FOE WITH NO BODY IS STILL OFFERED, because `#vitals_for` answers nil for
  # somebody with no stat block and nil is not dead. The doctor is what reports
  # that row (`hostile_without_a_stat_block`); this reader does not quietly drop
  # people it cannot measure.
  test "a hostile character with no stat block is a foe the doctor complains about" do
    bodiless = create(:character, :monster_without_a_stat_block, story: @story, location: @room,
                                                                 fullname: "The Sump")

    assert_nil @game.vitals_for(bodiless)
    assert_includes @game.foes_in(@room), bodiless
    assert_includes Story::Doctor.new(@story).findings.map(&:code), :hostile_without_a_stat_block
  end
end
