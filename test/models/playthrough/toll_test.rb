require "test_helper"

# WHAT ONE HAZARD TOOK OFF ONE BODY IN ONE GAME.
#
# The record, and the three things about it that are decisions rather than
# columns: it is NOT a `Playthrough::Blow` and must never open a fight, its
# sequence has the negative half of `Roll`'s space to itself so a hazard and a
# blow at one story moment can never be one die, and it reads its own words out
# of whichever of the two catalogues its source belongs to.
class Playthrough::TollTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @here = create(:location, story: @story, name: "The Causeway Court")
    @protagonist = create(:character, :protagonist, story: @story, level: 3, hit_die: 8)
    @game = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
  end

  test "it is valid out of the factory" do
    assert build(:playthrough_toll, playthrough: @game).valid?
  end

  test "damage, hp_after, a hazard, a sequence and a story moment are required" do
    toll = Playthrough::Toll.new(playthrough: @game, character: @protagonist, location: @here)

    assert_not toll.valid?
    assert_equal %i[hazard damage hp_after sequence story_timestamp].sort, toll.errors.attribute_names.sort
  end

  # THE SEQUENCE COUNTS DOWN, and that is the whole of how a toll and a blow at
  # one story moment stay two rolls: `Playthrough::Turn#check` uses 1..3 and
  # `Playthrough::Blow` counts up from `SEQUENCE_OFFSET`, so the negative half
  # belongs to this table alone and no offset has to be maintained.
  test "the sequence counts down off the rows" do
    assert_equal(-1, Playthrough::Toll.next_sequence(@game))
    create(:playthrough_toll, playthrough: @game)
    assert_equal(-2, Playthrough::Toll.next_sequence(@game))
  end

  test "a sequence in the blows' half is refused" do
    assert_not build(:playthrough_toll, playthrough: @game, sequence: 4).valid?
  end

  test "another game's tolls do not move this one's sequence" do
    create(:playthrough_toll, playthrough: create(:playthrough, story: @story))

    assert_equal(-1, Playthrough::Toll.next_sequence(@game))
  end

  # NIL IS THE WHOLE OF "the prose has not said this yet" -- the shape
  # `Playthrough::Blow#scene_id` has for the fight that is still on.
  test "untold is the rows no scene has carried" do
    untold = create(:playthrough_toll, playthrough: @game)
    create(:playthrough_toll, :told, playthrough: @game)

    assert_equal [ untold ], @game.tolls.untold.to_a
  end

  test "a room's toll reads its words out of the room's catalogue" do
    toll = create(:playthrough_toll, playthrough: @game, hazard: "flooded")

    assert_equal Location::HAZARDS.fetch("flooded").fetch(:words), toll.words
    assert_equal "The Causeway Court", toll.where_it_was
  end

  # A DOORWAY'S TOLL NAMES BOTH ENDS AND THE DIRECTION, because a one-way
  # hazard's whole content is which way you were going.
  test "a doorway's toll reads the other catalogue and names the direction" do
    hulk = create(:location, story: @story, name: "The Vestry Hulk")
    edge = create(:location_connection, :hazardous, location: @here, connected_location: hulk)
    toll = create(:playthrough_toll, playthrough: @game, hazard: "drop",
                                     location: hulk, location_connection: edge)

    assert_equal LocationConnection::HAZARDS.fetch("drop").fetch(:words), toll.words
    assert_equal "the way from The Causeway Court into The Vestry Hulk", toll.where_it_was
  end

  # A KEY NEITHER CATALOGUE HAS reads back as the bare key rather than as a
  # blank -- the honest nothing, and what keeps `rake game:doctor`'s
  # `location_with_an_unknown_hazard` a report rather than a crash.
  test "an unknown key reads back as itself" do
    toll = create(:playthrough_toll, playthrough: @game, hazard: "haunted")

    assert_equal "haunted", toll.words
  end

  test "a saved toll says so and cost nothing" do
    toll = create(:playthrough_toll, :saved, playthrough: @game)

    assert toll.saved?
    assert_equal 0, toll.damage
    assert_match(/got clear of/, toll.to_s)
  end

  test "a killing toll reads out with the numbers" do
    toll = create(:playthrough_toll, :killing, playthrough: @game, damage: 4)

    assert toll.killed?
    assert_equal "dead", toll.condition.in_words
    assert_match(/cost Hero Protagonist 4/, toll.to_s)
  end

  # A DOORWAY CAN GO IN THE ORDINARY COURSE OF A WORLD MOVING --
  # `WorldMechanic::ShuffleConnections` deletes and rewrites edges -- so the toll
  # keeps the measurement and loses only the pointer.
  test "a doorway the world moved leaves its tolls behind" do
    hulk = create(:location, story: @story, name: "The Vestry Hulk")
    edge = create(:location_connection, :hazardous, location: @here, connected_location: hulk)
    toll = create(:playthrough_toll, playthrough: @game, hazard: "drop",
                                     location: hulk, location_connection: edge)

    edge.destroy

    assert_nil toll.reload.location_connection_id
    assert_equal LocationConnection::HAZARDS.fetch("drop").fetch(:words), toll.words,
                 "the words still come out of the catalogue the key belongs to"
    assert_equal "The Vestry Hulk", toll.where_it_was
  end

  # THE ROOM'S OWN HISTORY GOES WITH THE ROOM, which is the answer
  # `playthrough_blows` already gives and is why `location_id` is NOT NULL.
  test "it goes when the room does" do
    create(:playthrough_toll, playthrough: @game, location: @here)

    assert_difference("Playthrough::Toll.count", -1) { @here.destroy }
  end

  # NULLIFIED, on the blows' reasoning: the toll is what the dice did and the
  # Scene is only the paragraph that mentioned it. A toll with no scene reads as
  # UNTOLD, which after the paragraph is gone is the truth about it.
  test "a scene that is deleted leaves its toll untold rather than gone" do
    toll = create(:playthrough_toll, :told, playthrough: @game)

    assert_difference("Playthrough::Toll.count", 0) { toll.scene.destroy }
    assert_nil toll.reload.scene_id
  end

  test "it goes when the game does" do
    create(:playthrough_toll, playthrough: @game)

    assert_difference("Playthrough::Toll.count", -1) { @game.destroy }
  end
end
