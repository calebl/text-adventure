require "test_helper"

# THE WORLD'S HALF OF A ROUND: every live foe in the room acts, in `id` order.
#
# The captain's call C5 -- a round IS the turn -- and the three decisions it
# rests on, each with a test: a refused line buys nobody a round (the caller's
# job, asserted in `Playthrough::TurnTest` and `Playthrough::MechanicsTest`),
# the foes in the room you LEFT act before you go, and a game that has ended
# stops the exchange where it stands.
class Playthrough::RiposteTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @room = create(:location, story: @story, name: "The Bell Chamber")
    @elsewhere = create(:location, story: @story, name: "The Stair")
    @protagonist = create(:character, :protagonist, story: @story, level: 3, hit_die: 8)
    @game = create(:playthrough, story: @story, character: @protagonist, current_location: @room)
  end

  def riposte(location: @room, round: 1)
    Playthrough::Riposte.new(@game).run!(location: location, round: round)
  end

  test "an ordinary room answers nothing" do
    create(:character, story: @story, location: @room, fullname: "Grenn Ollivar")

    assert_equal [], riposte
    assert_equal 0, @game.blows.count
  end

  test "every live foe present strikes the party once" do
    first = create(:character, :monster, story: @story, location: @room, fullname: "Marek Sollen")
    second = create(:character, :monster, story: @story, location: @room, fullname: "Ada Threnn")

    blows = riposte

    assert_equal [ first, second ], blows.map(&:attacker)
    assert_equal [ @protagonist, @protagonist ], blows.map(&:target)
    assert_equal [ 1, 1 ], blows.map(&:round), "one exchange is one round however many swung"
  end

  # `id` ORDER, which is the app's own answer to "in what order do two records
  # in one room come out" -- reused rather than reinvented, so there is no
  # second ordering and no initiative system to build.
  test "they act in id order" do
    late = create(:character, :monster, story: @story, location: @room, fullname: "Zed Last")
    early = create(:character, :monster, story: @story, location: @room, fullname: "Ada First")

    assert_equal [ late.id, early.id ].sort, riposte.map(&:attacker_id)
  end

  test "a foe this game has killed does not act" do
    down = create(:character, :monster, story: @story, location: @room, fullname: "Marek Sollen")
    Playthrough::Turn.new(@game).harm!(down, down.max_hp)

    assert_equal [], riposte
  end

  # A GAME THAT IS OVER IS A GAME NOTHING WILL EVER CHANGE AGAIN, so the second
  # hound does not get to bite a corpse.
  test "it stops the moment the player is dead" do
    3.times { |n| create(:character, :monster, story: @story, location: @room, fullname: "Hound #{n}") }
    Playthrough::Turn.new(@game).harm!(@protagonist, @protagonist.max_hp - 1)

    blows = riposte

    assert_predicate @game.reload, :over?
    assert_equal 1, blows.size, "the first blow ended the game and the rest did not land"
    assert_equal 1, @game.blows.count
  end

  test "a playthrough with no protagonist has nobody to strike" do
    create(:character, :monster, story: @story, location: @room)
    game = create(:playthrough, story: @story, current_location: @room)

    assert_equal [], Playthrough::Riposte.new(game).run!(location: @room, round: 1)
  end

  test "nowhere answers nothing" do
    create(:character, :monster, story: @story, location: @room)

    assert_equal [], riposte(location: nil)
  end

  # THE ROOM YOU LEFT, which is what a move out of a fight costs: you turned
  # your back. The blow belongs to the room it was thrown in, which is what
  # `Playthrough::Fight` reads to know the fight is over.
  test "the blow belongs to the room it was thrown in and not to where the party ended up" do
    create(:character, :monster, story: @story, location: @room, fullname: "Marek Sollen")
    Playthrough::Turn.new(@game).stand_in!(@elsewhere)

    blows = riposte(location: @room)

    assert_equal [ @room ], blows.map(&:location)
    assert_predicate Playthrough::Fight.new(@game), :over?
  end

  # A FOE THIS GAME MADE. `characters.hostile` is untouched; the mark is on the
  # per-playthrough row. See `Playthrough::Vitals#provoked?`.
  test "somebody the party provoked answers from the next turn" do
    # Level 3, so one d8 cannot kill him and this test is about provocation
    # rather than about which face came up.
    bystander = create(:character, story: @story, location: @room, fullname: "Grenn Ollivar",
                                   level: 3, hit_die: 8)
    assert_equal [], riposte

    Playthrough::Turn.new(@game).strike!(@protagonist, bystander, round: 1)

    assert_equal [ bystander ], riposte(round: 2).map(&:attacker)
    assert_not_predicate bystander.reload, :hostile?, "the world never learned about it"
  end
end
