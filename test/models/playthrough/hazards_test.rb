require "test_helper"

# THE WORLD'S OTHER HALF OF A ROUND: the place you are standing in, and the way
# you got into it.
#
# Every branch of `Playthrough::Hazards`, and the decisions each one rests on: a
# room's hazard is paid at the moment its catalogue entry names and at no other,
# a doorway's is paid in ONE direction because it is on one row, `save: nil` is
# a real hazard and not an omission, and a hazard reaches hit points through
# `Playthrough::Turn#harm!` -- so it can kill, and killing the player ends the
# game exactly as a blow does.
#
# ABILITIES ARE PINNED AT THE ENDS OF `Character::ABILITY_RANGE` wherever an
# outcome matters, which is how a test asserts a rule rather than a die: at
# strength 18 the d20 comes up at or under it 18 times in 20 and at 3 it does
# not, so a test that wanted a certain save would still be a lottery. Nothing
# here asserts what a toll COST unless the save was impossible to make or
# impossible to miss; what it asserts is that the toll was PAID, which is the
# same line `rake game:sweep` draws.
class Playthrough::HazardsTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @here = create(:location, story: @story, name: "The Causeway Court")
    @there = create(:location, story: @story, name: "The Tide Post")
    @protagonist = create(:character, :protagonist, story: @story, level: 3, hit_die: 8,
                                                    strength: 12, dexterity: 12, will: 12)
    @game = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
  end

  def hazards = Playthrough::Hazards.new(@game)

  # A BODY SMALL ENOUGH FOR ONE DIE TO FINISH, and it has to be BUILT that way
  # rather than shrunk afterwards: `Playthrough::Vitals` stamps `hp_current`
  # with the maximum the body had when the row was written, so a protagonist
  # levelled down after a game has started is holding more than it can hold --
  # which the record correctly refuses. `abilities: nil` throughout, so no save
  # is ever made and nothing below depends on a die.
  def a_fragile_game
    weak = create(:character, story: @story, fullname: "Fragile Vance",
                             level: 1, hit_die: 6, strength: nil, dexterity: nil, will: nil)
    create(:playthrough, story: @story, character: weak, current_location: @here)
  end

  def door!(from, to, **attributes)
    create(:location_connection, location: from, connected_location: to, **attributes)
  end

  # --- a room's own hazard --------------------------------------------------

  test "an ordinary room costs nothing on arrival" do
    assert_equal [], hazards.on_arrival!(@there, from: @here)
    assert_equal 0, @game.tolls.count
  end

  test "a room whose hazard is paid on arrival is paid on arrival" do
    @there.update!(hazard: "flooded", hazard_die: 4)

    tolls = hazards.on_arrival!(@there, from: @here)

    assert_equal 1, tolls.size
    assert_equal "flooded", tolls.first.hazard
    assert_equal @there, tolls.first.location
    assert_nil tolls.first.location_connection, "a room's hazard is not a doorway's"
  end

  # THE TWO `when:` VALUES REACH TWO BRANCHES, and neither one answers for the
  # other. A room that hurts you for staying does not charge for arriving, and
  # a room that charges for arriving does not go on charging.
  test "an every_turn room is free to walk into and costs to stay in" do
    @there.update!(hazard: "airless", hazard_die: 4)

    assert_equal [], hazards.on_arrival!(@there, from: @here)
    assert_equal 1, hazards.every_turn!(location: @there).size
  end

  test "an on_arrival room is free to stay in" do
    @there.update!(hazard: "flooded", hazard_die: 4)

    assert_equal [], hazards.every_turn!(location: @there)
  end

  # A key the catalogue does not have rolls nothing at all, which is what makes
  # `rake game:doctor`'s `location_with_an_unknown_hazard` a report rather than
  # a crash. Written past the validation, because that is the only way a row
  # gets there.
  test "a hazard the catalogue has no entry for costs nothing" do
    @there.update_columns(hazard: "haunted", hazard_die: 4)

    assert_equal [], hazards.on_arrival!(@there.reload, from: @here)
    assert_equal [], hazards.every_turn!(location: @there)
  end

  test "half a hazard is refused by the record" do
    assert_raises(ActiveRecord::RecordInvalid) { @there.update!(hazard: "flooded") }
    assert_raises(ActiveRecord::RecordInvalid) { @there.reload.update!(hazard_die: 4) }
  end

  # --- a doorway's hazard, and it is one-way by construction ----------------

  test "the doorway that was walked is paid and the one back is not" do
    door!(@here, @there, hazard: "drop", hazard_die: 4)
    door!(@there, @here)

    out = hazards.on_arrival!(@there, from: @here)
    assert_equal 1, out.size
    assert_equal "drop", out.first.hazard
    assert_equal @there, out.first.location, "the toll is paid where you end up"
    assert_equal @here, out.first.location_connection.location

    assert_equal [], hazards.on_arrival!(@here, from: @there), "the way back carries no hazard"
  end

  test "a party that was nowhere pays no doorway" do
    door!(@here, @there, hazard: "drop", hazard_die: 4)

    assert_equal [], hazards.on_arrival!(@there, from: nil)
  end

  # THE DOORWAY FIRST AND THE ROOM SECOND, because that is the order they
  # happen in: you cross, and then you are standing there.
  test "a hazardous door into a hazardous room is two tolls in that order" do
    door!(@here, @there, hazard: "drop", hazard_die: 4)
    @there.update!(hazard: "flooded", hazard_die: 4)

    tolls = hazards.on_arrival!(@there, from: @here)

    assert_equal %w[drop flooded], tolls.map(&:hazard)
    assert_equal [ false, true ], tolls.map { |toll| toll.location_connection.nil? }
  end

  # --- the save -------------------------------------------------------------

  # `save: nil` IS A REAL HAZARD. `airless` names no ability, so no d20 is
  # thrown and the die always lands -- which is the whole reason the catalogue
  # can say nil and the reason `saved` is a column rather than `damage.zero?`.
  test "a hazard with no save is never saved against" do
    @there.update!(hazard: "airless", hazard_die: 4)

    toll = hazards.every_turn!(location: @there).first

    assert_not toll.saved?
    assert toll.damage.positive?
  end

  # A BODY THAT CANNOT ROLL THE SAVE DOES NOT GET ONE. `Character#check` answers
  # nil for somebody with no abilities, and inventing a pass would be inventing
  # the number the column is nullable to avoid.
  test "a body with no abilities does not save" do
    game = a_fragile_game
    @there.update!(hazard: "flooded", hazard_die: 4)

    toll = Playthrough::Hazards.new(game).on_arrival!(@there, from: @here).first

    assert_not toll.saved?
    assert toll.damage.positive?
  end

  # AT STRENGTH 18 THE SAVE IS 18 IN 20 AND AT 3 IT IS 3 IN 20, so neither is
  # assertable on one roll. What IS assertable without a die is that a saved
  # toll costs nothing and an unsaved one costs something -- so the two are
  # pinned off the ROW rather than off the outcome.
  test "a saved toll costs nothing and an unsaved one costs something" do
    @there.update!(hazard: "flooded", hazard_die: 4)

    toll = hazards.on_arrival!(@there, from: @here).first

    if toll.saved?
      assert_equal 0, toll.damage
      assert_equal @protagonist.max_hp, toll.hp_after
    else
      assert toll.damage.between?(1, 4), "one die of the room's hazard_die"
      assert_equal @protagonist.max_hp - toll.damage, toll.hp_after
    end
  end

  # THE SEED IS THE ROLL'S IDENTITY. Two hazards paid at one story moment are
  # two rolls because `Playthrough::Toll.next_sequence` counts the rows, and the
  # tolls have the NEGATIVE half of the sequence space to themselves so a blow
  # and a toll at one moment can never be one die.
  test "two tolls at one moment are two different rolls" do
    door!(@here, @there, hazard: "drop", hazard_die: 4)
    @there.update!(hazard: "flooded", hazard_die: 4)

    sequences = hazards.on_arrival!(@there, from: @here).map(&:sequence)

    assert_equal [ -1, -2 ], sequences
    assert sequences.all?(&:negative?), "the checks and the blows have the positive half"
  end

  test "the same walk in two processes throws the same dice" do
    @there.update!(hazard: "airless", hazard_die: 10)

    first = hazards.every_turn!(location: @there).first
    Playthrough::Toll.delete_all
    Playthrough::Vitals.delete_all
    second = Playthrough::Hazards.new(@game.reload).every_turn!(location: @there).first

    assert_equal first.damage, second.damage
  end

  # --- what it writes, and what it must not --------------------------------

  test "it writes no world data at all" do
    @there.update!(hazard: "flooded", hazard_die: 4)
    door!(@here, @there, hazard: "drop", hazard_die: 4)

    hazards.on_arrival!(@there, from: @here)

    assert_equal "flooded", @there.reload.hazard
    assert_equal 4, @there.hazard_die
    assert_equal "drop", LocationConnection.walked(@here, @there).hazard
    assert_equal [ 12, 12, 12 ], Character::ABILITIES.map { |ability| @protagonist.reload[ability] }
  end

  # A HAZARD IS NEVER A BLOW. `Playthrough::Fight#open_blows` is "the fight that
  # is still on", so a hazard written into that table would open a fight nobody
  # was in and `#over?` would close it with a `Scene` on the same turn.
  test "it opens no fight" do
    @there.update!(hazard: "airless", hazard_die: 4)

    hazards.every_turn!(location: @there)

    assert_equal 0, @game.blows.count
    assert_not Playthrough::Fight.new(@game).on?
  end

  # --- death ----------------------------------------------------------------

  # THE ONE WRITER IS `#harm!`, so a hazard ends a game by the same statement a
  # blow does and there is no second place a playthrough can end. `airless`
  # names no ability, so nothing here depends on a save.
  test "a hazard can take the last hit point and end the game" do
    game = a_fragile_game
    @there.update!(hazard: "airless", hazard_die: 10)
    Playthrough::Turn.new(game).harm!(game.character, game.character.max_hp - 1)

    toll = Playthrough::Hazards.new(game).every_turn!(location: @there).first

    assert_equal 0, toll.hp_after
    assert toll.killed?
    assert game.reload.over?
  end

  test "a game that is already over pays nothing" do
    @there.update!(hazard: "airless", hazard_die: 4)
    @game.end!

    assert_equal [], hazards.every_turn!(location: @there)
    assert_equal [], hazards.on_arrival!(@there, from: @here)
    assert_equal 0, @game.tolls.count
  end

  # A DOORWAY THAT TOOK THE LAST HIT POINT MUST NOT BE FOLLOWED BY THE ROOM
  # TAKING ANOTHER OFF A CORPSE -- `Playthrough::Riposte`'s "the second hound
  # does not get to bite a corpse" one table over.
  test "a doorway that kills stops the room from charging" do
    game = a_fragile_game
    door!(@here, @there, hazard: "undertow", hazard_die: 10)
    @there.update!(hazard: "airless", hazard_die: 10)
    Playthrough::Turn.new(game).harm!(game.character, game.character.max_hp - 1)

    tolls = Playthrough::Hazards.new(game).on_arrival!(@there, from: @here)

    assert_equal 1, tolls.size
    assert_equal "undertow", tolls.first.hazard, "the room never got its turn at a corpse"
    assert game.reload.over?
  end

  test "a body with no stat block pays no toll" do
    nobody = create(:character, story: @story, fullname: "Unrolled Vance", level: nil, hit_die: nil)
    game = create(:playthrough, story: @story, character: nobody, current_location: @here)
    @there.update!(hazard: "airless", hazard_die: 4)

    assert_equal [], Playthrough::Hazards.new(game).every_turn!(location: @there)
    assert_equal 0, Playthrough::Toll.count, "and nothing is left behind by the transaction"
  end

  test "a playthrough with no protagonist pays nothing" do
    game = create(:playthrough, story: @story, character: nil, current_location: @here)
    @there.update!(hazard: "airless", hazard_die: 4)

    assert_equal [], Playthrough::Hazards.new(game).every_turn!(location: @there)
  end

  test "nowhere costs nothing" do
    assert_equal [], hazards.on_arrival!(nil, from: @here)
    assert_equal [], hazards.every_turn!(location: nil)
  end
end
