require "test_helper"

# WHAT THE PANEL SAYS, AND THAT EVERY WORD OF IT IS A RECORD READ BACK.
#
# The captain's call C9 of 2026-09-05 -- ***"go with buttons for now"*** -- is
# shape (a) of the combat scout's §12: buttons posting fixed commands, condition
# lines rather than bars, no narrator and no classifier. This file is the half
# of it that can be asserted without a browser: what is on the panel, what is
# not, and that a fight is entered and left by DERIVATION and never by a flag.
#
# NOTHING HERE MAKES A MODEL CALL, and it is not stubbed out to keep it that
# way: `Playthrough::Battle` reads `Playthrough#foes_in`, `#cast_in`,
# `#vitals_for`, `#exits` and `Playthrough::Fight`, all of which are queries.
class Playthrough::BattleTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @room = create(:location, story: @story, name: "The Bell of Saint Aravel")
    @stair = create(:location, story: @story, name: "The Stair")
    create(:location_connection, location: @room, connected_location: @stair)
    create(:location_connection, location: @stair, connected_location: @room)
    # LEVEL 3 AND A d8, WHICH IS 18 HIT POINTS -- the captain's call C1 and what
    # the seeded worlds give a protagonist. Fixed here for `Playthrough::Fight`'s
    # stated reason: the dice are seeded off row ids, so no fixture may depend
    # on a face coming up.
    @protagonist = create(:character, :protagonist, story: @story, level: 3, hit_die: 8)
    @monster = create(:character, :monster, story: @story, location: @room, fullname: "Marek Sollen",
                                            level: 3, hit_die: 8)
    @game = create(:playthrough, story: @story, character: @protagonist, current_location: @room)
    @turn = Playthrough::Turn.new(@game)
  end

  def battle = Playthrough::Battle.new(@game)

  # THE DERIVATION, IN BOTH DIRECTIONS. There is no battle flag: the panel is on
  # when `Playthrough#foes_in` answers with somebody and off when it does not,
  # so nothing can go stale and there is nothing to reconcile when a fight ends.
  test "a room with nobody hostile in it is not a fight" do
    @game.update!(current_location: @stair)

    assert_not_predicate battle, :on?
  end

  test "a room with somebody hostile in it is a fight, with no flag anywhere" do
    assert_predicate battle, :on?
    assert_equal [ @monster ], battle.foes
  end

  # THE PARTY IS NOT A FOE, however the panel is entered: `#foes_in` drops the
  # protagonist and their companions before it reads a mark.
  test "the party is on the panel and never among the foes" do
    names = battle.bodies.map(&:name)

    assert_equal [ "Hero Protagonist", "Marek Sollen" ], names
    assert_equal [ "you", "hostile" ], battle.bodies.map(&:mark)
  end

  # NUMBERS AND NOT BARS, and not an adjective either: `2 of 6` is the whole of
  # the condition line. The scout's §12.2 cost 3 and §15.6 -- a hit-point bar is
  # a visual vocabulary `ta-api-iface` has not decided yet.
  test "a condition line is the numbers, out of this game's own vitals" do
    assert_equal [ "18 of 18", "18 of 18" ], battle.bodies.map(&:state)

    @turn.harm!(@monster, 5)

    assert_equal [ "18 of 18", "13 of 18" ], battle.bodies.map(&:state)
  end

  # A BODY WITH NO STAT BLOCK SAYS SO rather than being given one. That state is
  # a `rake game:doctor` finding, and a view that invented a maximum for it
  # would be the thing `characters.level` is nullable to avoid.
  test "a body written before the stat block columns says so" do
    @monster.update_columns(level: nil, hit_die: nil)

    assert_equal "no stat block", battle.bodies.last.state
  end

  # TWO WAYS TO BE A FOE AND THEY ARE DIFFERENT RECORDS: `characters.hostile` is
  # the WORLD's and a seed file wrote it; `playthrough_vitals.provoked_at` is
  # THIS GAME's and the party wrote it by swinging first.
  test "somebody this game provoked is on the panel, marked as this game's own" do
    landlord = create(:character, story: @story, location: @room, fullname: "Grenn Ollivar")
    @monster.update!(hostile: false)

    assert_not_predicate battle, :on?

    @turn.strike!(@protagonist, landlord, round: 1)

    assert_predicate battle, :on?
    assert_equal [ "Grenn Ollivar" ], battle.foes.map(&:fullname)
    assert_equal [ "you", "provoked" ], battle.bodies.map(&:mark)
  end

  # THE ROUND IS OFF THE ROWS, out of `Playthrough::Fight#next_round` -- the
  # same number `Playthrough::Turn#play` hands every blow of the turn.
  test "the round the next line lands on counts up with the fight" do
    assert_equal 1, battle.round

    @turn.strike!(@protagonist, @monster, round: 1)
    @turn.strike!(@monster, @protagonist, round: 1)

    assert_equal 2, battle.round
  end

  # THE LAST EXCHANGE AND NOT THE WHOLE FIGHT: the panel says what just
  # happened, and the whole of it is in the log once the fight closes.
  test "the last exchange is the blows of the round just fought" do
    assert_empty battle.last_exchange

    @turn.strike!(@protagonist, @monster, round: 1)
    @turn.strike!(@monster, @protagonist, round: 1)
    @turn.strike!(@protagonist, @monster, round: 2)

    exchange = battle.last_exchange

    assert_equal 1, exchange.size
    assert_equal 2, exchange.first.round
    # The ENGINE's own sentence about its own dice, reused verbatim from
    # `Playthrough::Blow#to_s` so the browser and `rake game:mechanics` cannot
    # describe one blow two ways.
    assert_match(/Hero Protagonist hit Marek Sollen for \d+ \(round 2\)/, exchange.first.to_s)
  end

  # THE BUTTONS ARE SLASHED LINES, which is the whole of why a round costs
  # nothing: `Playthrough::Grammar` claims a line beginning with `/` and the
  # classifier is never called (the captain's ruling of 2026-09-05).
  test "a strike button posts a slashed line the fixed grammar reads" do
    assert_equal [ "strike Marek Sollen" ], battle.strikes.map(&:label)
    assert_equal [ "/attack Marek Sollen" ], battle.strikes.map(&:command)

    reading = Playthrough::Grammar.new(@game).reading_first("/attack Marek Sollen")

    assert_predicate reading, :resolved?
    assert_equal @monster, reading.intent.subject
  end

  # THE WAY OUT IS ALWAYS OFFERED -- the captain's call C1, a fight is always
  # escapable by leaving the room. It is the one button that costs a model call,
  # and it costs it because a move realizes a room and narrates arriving.
  test "every exit is a way out of the fight" do
    assert_equal [ "go to The Stair" ], battle.ways_out.map(&:label)
    assert_equal [ "/go The Stair" ], battle.ways_out.map(&:command)

    reading = Playthrough::Grammar.new(@game).reading_first("/go The Stair")

    assert_equal @stair, reading.intent.subject
  end

  # THE SLICE 5 SEAM. `throw` is not in `Playthrough::Grammar::VERBS` on this
  # branch, so there is no line a button could post that the engine would read,
  # and a button posting one would be refused as an unknown verb. See
  # `Playthrough::Battle#throws` for what fills it.
  test "there are no throw buttons until the throw verb exists" do
    assert_empty battle.throws
    assert_not Playthrough::Grammar::RESOLVING.key?("throw")
  end

  # THE FIGHT ENDS BY THE RECORDS AND THE PANEL GOES WITH IT, all three ways.
  test "killing the last foe takes the panel away" do
    @turn.harm!(@monster, @monster.max_hp)

    assert_not_predicate battle, :on?
  end

  test "walking out takes the panel away, with the fight still standing behind you" do
    @turn.strike!(@protagonist, @monster, round: 1)
    @game.update!(current_location: @stair)

    assert_not_predicate battle, :on?
  end

  # A DEAD PLAYER IS NOT IN A FIGHT whatever is standing over them:
  # `Playthrough::DeathNotice` has the screen, and every typed line is refused
  # in front of the classifier.
  test "a game that is over shows no panel" do
    @turn.harm!(@protagonist, @protagonist.max_hp)

    assert_predicate @game.reload, :over?
    assert_not_predicate battle, :on?
  end
end
