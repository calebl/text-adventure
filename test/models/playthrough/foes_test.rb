require "test_helper"

# WHO IS FIGHTING THIS PARTY, HERE, IN THIS GAME. `Playthrough#foes_in` is the
# one reader of it, and what it is for is the join: the WORLD says who is
# hostile (`characters.hostile`) and a GAME says who is still standing
# (`playthrough_vitals`). Either half read alone is the wrong answer, and this
# is the test that says so.
#
# SINCE THE CAPTAIN'S SIXTH RULING OF 2026-09-05 THERE ARE TWO WAYS ONTO THAT
# LIST -- *"anyone can be attacked"* -- so the join is three-cornered now: the
# world's `characters.hostile`, this game's `playthrough_vitals.provoked_at`,
# and this game's dead. One reader, so a fight, a read-out and a sweep cannot
# come to three different answers.
class Playthrough::FoesTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @room = create(:location, story: @story, name: "The Bell Chamber")
    @elsewhere = create(:location, story: @story, name: "The Stair")
    # Level 3 with a d8 -- 18 hit points, the captain's call C1 -- so a single
    # answering blow cannot end a test that is not about dying.
    @protagonist = create(:character, :protagonist, story: @story, level: 3, hit_die: 8)
    @game = create(:playthrough, story: @story, character: @protagonist, current_location: @room)

    @monster = create(:character, :monster, story: @story, location: @room, fullname: "Marek Sollen")
    @bystander = create(:character, story: @story, location: @room, fullname: "Grenn Ollivar",
                                    level: 3, hit_die: 8)
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

  # TWO WAYS TO BE A FOE, AND THE SECOND IS THIS GAME'S OWN. The captain's sixth
  # ruling of 2026-09-05: *"anyone can be attacked"*, and being attacked makes
  # somebody a foe for THIS playthrough. `characters.hostile` never moves --
  # `EngineSweep::Invariants#hostility_unmoved` is that assertion after a walk,
  # and this is it in a fixture.
  test "somebody this game provoked is a foe and the world never hears about it" do
    Playthrough::Turn.new(@game).strike!(@protagonist, @bystander, round: 1)

    assert_includes @game.foes_in(@room), @bystander
    assert_not_predicate @bystander.reload, :hostile?
    assert @game.provoked?(@bystander)
  end

  test "one game's provocation is not another game's" do
    other = create(:playthrough, story: @story, character: @protagonist, current_location: @room)
    Playthrough::Turn.new(@game).strike!(@protagonist, @bystander, round: 1)

    assert_not_includes other.foes_in(@room), @bystander
    assert_not other.provoked?(@bystander)
  end

  test "a provoked person this game has killed is not a foe either" do
    turn = Playthrough::Turn.new(@game)
    turn.strike!(@protagonist, @bystander, round: 1)
    turn.harm!(@bystander, @bystander.max_hp)

    assert_equal [ @monster ], @game.foes_in(@room)
  end

  # THE PARTY IS NEVER IN IT, and it is excluded outright rather than left to
  # the records: `#cast_in` ADDS the protagonist to a room's cast, and being
  # struck marks a body provoked whoever struck it -- so without the guard one
  # blow from a hound would put the player on the list of people the hounds have
  # to fight.
  test "the player struck by a foe does not become their own foe" do
    Playthrough::Turn.new(@game).strike!(@monster, @protagonist, round: 1)

    assert @game.provoked?(@protagonist)
    assert_equal [ @monster ], @game.foes_in(@room)
  end

  test "nobody has been provoked in a game nobody has swung in" do
    assert_not @game.provoked?(@bystander)
    assert_not @game.provoked?(nil)
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
