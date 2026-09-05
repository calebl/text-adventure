require "test_helper"

# THROWING SOMETHING, AND THE FOUR OUTCOMES THE ENGINE DECIDES BETWEEN.
#
# The captain's request of 2026-09-05, `data/ta-combat-scout` §13: *"I want
# players to be able to pick up items and throw them based on a strength
# check."*
#
# WHY EVERY OUTCOME IS PINNED HERE AND NOT IN A SWEEP SCRIPT. `Roll`'s seed is
# built out of ROW IDS, so whether a given throw passes is not re-derivable
# across two databases -- and no bulk makes a pass certain either, because the
# best case in the app is strength 18 against a `light` thing, which is
# `d20 <= 18`. So `rake game:sweep` pins the refusals and the act
# (`lib/engine_sweep/scripts/a-thing-can-be-thrown.yml` says so in full), and
# this file hands `#throw_item!` its own `rng:` and pins what the die decided.
class Playthrough::TurnThrowTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @here = create(:location, story: @story, name: "Ward Office 12")
    @there = create(:location, story: @story, name: "The Supply Closet")
    @vance = create(:character, :protagonist, story: @story, fullname: "Odile Vance",
                                              level: 3, hit_die: 8,
                                              strength: 9, dexterity: 11, will: 15)
    @rowe = create(:character, story: @story, fullname: "Halkett Rowe", location: @here,
                               level: 1, hit_die: 8, strength: 11, dexterity: 9, will: 13)
    @game = create(:playthrough, story: @story, character: @vance, current_location: @here)
    @turn = Playthrough::Turn.new(@game)
  end

  # A GENERATOR THAT PASSES AND ONE THAT DOES NOT, built rather than searched
  # for: the first draw is the d20 and the second is the damage die, so a stub
  # answering a fixed sequence is the honest way to pin an outcome.
  def rolling(*faces)
    Class.new do
      def initialize(faces) = @faces = faces
      def rand(range) = @faces.shift.clamp(range.first, range.last)
    end.new(faces)
  end

  def carried(name: "Ward Office 12 daybook", **traits)
    create(:item, *traits.fetch(:traits, []), name: name, character: nil, playthrough: @game)
  end

  # --- the refusal, which needs no die --------------------------------------

  # AN IMMOVABLE THING IS NOT A HARD THROW, IT IS NOT A THROW. `Item::BULK` has
  # no penalty for it, so nothing is rolled and nothing moves -- and the loop
  # never even gets here, because `Intent#refused?` answers first.
  test "an immovable thing is refused, no die is thrown and no row moves" do
    press = create(:item, :lying, :immovable, name: "filing press", location: @here)

    outcome = @turn.throw_item!(press, at: @rowe, round: 1)

    assert_predicate outcome, :immovable?
    assert_nil outcome.check, "no die was thrown, so there is no check to read"
    assert_not_predicate outcome, :landed?
    assert_equal @here, press.reload.location
    assert_predicate @game.vitals_for(@rowe), :unhurt?
    assert_empty @game.blows
  end

  test "the loop refuses an immovable throw in front of the dispatch" do
    press = create(:item, :lying, :immovable, name: "filing press", location: @here)
    intent = Playthrough::Classifier::Intent.new(action: :throw, item: press, at: @rowe)

    assert_predicate intent, :throws_the_immovable?
    assert_predicate intent, :refused?
    assert_equal :immovable, Playthrough::Refusal.for(intent, typed: "throw the press at Rowe").kind
  end

  # --- the failed lift ------------------------------------------------------

  # A FUMBLE IS A TURN THE ENGINE PLAYED. It read the line, resolved two
  # records, threw a die and the answer was failure -- so nothing moved and the
  # turn was still spent, which is the whole distinction
  # `Playthrough::Refusal`'s header draws.
  test "a failed lift moves nothing, hurts nobody and provokes nobody" do
    daybook = carried

    outcome = @turn.throw_item!(daybook, at: @rowe, round: 1, rng: rolling(20, 6))

    assert_predicate outcome, :fumbled?
    assert_not_predicate outcome, :landed?
    assert_predicate outcome.check, :failed?
    assert_equal 7, outcome.check.target, "strength 9 less a handy thing's 2"
    assert_predicate daybook.reload, :carried?
    assert_predicate @game.vitals_for(@rowe), :unhurt?
    assert_not @game.provoked?(@rowe)
    assert_empty @game.blows
    assert_nil outcome.blow
  end

  # AT A TARGET OF ZERO OR LESS NO DIE IS THROWN AT ALL, which is
  # `Character::Check#impossible?` and the one fumble that is certain. It is
  # still a fumble and not a refusal: the thing DOES move for somebody, just not
  # for this body.
  test "a body too weak for the thing fumbles without rolling" do
    weakling = create(:character, :protagonist, story: create(:story), strength: 4, dexterity: 10, will: 10,
                                                level: 1, hit_die: 6)
    game = create(:playthrough, story: weakling.story, character: weakling,
                                current_location: create(:location, story: weakling.story))
    slate = create(:item, :heavy, name: "Assize tide-slate", character: nil, playthrough: game)

    outcome = Playthrough::Turn.new(game).throw_item!(slate, at: create(:character, story: weakling.story), round: 1)

    assert_predicate outcome, :fumbled?
    assert_predicate outcome.check, :impossible?
    assert_not_predicate outcome.check, :rolled?
    assert_predicate slate.reload, :carried?
  end

  # --- a hit ----------------------------------------------------------------

  # ONE TRANSACTION, TWO STATEMENTS: the thing leaves the hands through
  # `#put_down!` and the body loses hit points through `#harm!`. No new writer.
  test "a hit lands the thing at their feet and takes hit points off them" do
    daybook = carried

    outcome = @turn.throw_item!(daybook, at: @rowe, round: 1, rng: rolling(1, 6))

    assert_predicate outcome, :struck?
    assert_predicate outcome, :landed?
    assert_predicate outcome.check, :passed?
    assert_equal @here, daybook.reload.location, "it is lying at their feet, in this game"
    assert_not_predicate daybook, :carried?
    assert_equal 6, outcome.damage, "a handy thing is a d6"
    assert_equal 2, @game.vitals_for(@rowe).hp, "8 hit points less a d6 of 6"
  end

  # A THROWN THING DEALS ONE DIE OF ITS OWN BULK and never one of the thrower's
  # `hit_die`, which is what `#strike!`'s `damage:` is for. The captain's call
  # C8: light d4, handy d6, heavy d8.
  test "the damage die is the thing's bulk and not the thrower's hit die" do
    Item::THROWN_DAMAGE.each do |bulk, die|
      thing = create(:item, name: "a #{bulk} thing", character: nil, playthrough: @game, bulk: bulk)
      outcome = @turn.throw_item!(thing, at: @rowe, round: 1, rng: rolling(1, die))

      assert_equal die, outcome.damage, bulk
      @turn.mend!(@rowe, 99)
    end

    assert_equal 8, @vance.hit_die, "and the thrower's own die was never asked for"
  end

  # A HIT IS A BLOW IN EVERY RESPECT, so the riposte and the fight-end rule see
  # it without knowing what threw it -- the captain's sixth ruling of
  # 2026-09-05, *"anyone can be attacked"*, applied to a thing rather than a
  # fist.
  test "a hit writes a blow, marks the victim provoked and opens a fight" do
    daybook = carried

    outcome = @turn.throw_item!(daybook, at: @rowe, round: 2, rng: rolling(1, 3))

    blow = outcome.blow
    assert_equal @vance, blow.attacker
    assert_equal @rowe, blow.target
    assert_equal @here, blow.location
    assert_equal 2, blow.round
    assert_equal 3, blow.damage
    assert @game.provoked?(@rowe)
    assert_includes @game.foes_in(@here), @rowe
    assert_predicate Playthrough::Fight.new(@game), :on?
  end

  # AND A HIT CAN KILL, which is what C8's 37.3% is a statement about. `#harm!`
  # spills what the body was holding in the same transaction.
  test "a heavy thing can take the last hit point" do
    chair = create(:item, :heavy, name: "reading chair", character: nil, playthrough: @game)
    @turn.harm!(@rowe, 5)

    outcome = @turn.throw_item!(chair, at: @rowe, round: 1, rng: rolling(1, 8))

    assert_predicate @game.vitals_for(@rowe), :dead?
    assert_predicate outcome.blow, :killed?
    assert_not_includes @game.cast_in(@here), @rowe
    assert_not_predicate @game, :over?, "an NPC dying does not end the game"
  end

  # A BODY THE RECORDS HAVE NO STAT BLOCK FOR IS THE HONEST NOTHING `#harm!`
  # gives one: the thing still landed at their feet, and no blow was recorded.
  test "a hit on somebody with no stat block lands the thing and writes no blow" do
    ghost = create(:character, story: @story, fullname: "Perrin Lasco", location: @here,
                               level: nil, hit_die: nil)
    daybook = carried

    outcome = @turn.throw_item!(daybook, at: ghost, round: 1, rng: rolling(1, 6))

    assert_predicate outcome, :struck?
    assert_nil outcome.blow
    assert_equal @here, daybook.reload.location
    assert_empty @game.blows
  end

  # --- through a doorway ----------------------------------------------------

  # `#put_down!(into:)` IS THE WHOLE OF IT: one keyword, the same statement, and
  # the header's rule holds -- `playthrough` is not cleared, so the row stays
  # this game's copy.
  test "a throw through a doorway leaves the thing lying in the next room" do
    daybook = carried

    outcome = @turn.throw_item!(daybook, at: @there, round: 1, rng: rolling(1))

    assert_predicate outcome, :thrown?
    assert_predicate outcome, :landed?
    assert_equal @there, daybook.reload.location
    assert_equal @game, daybook.playthrough, "it is still this game's own copy"
    assert_empty @game.blows, "a doorway is not a body"
    assert_equal @here, @game.reload.current_location, "and the party did not follow it"
  end

  test "a throw at a room draws one die and a throw at a person draws two" do
    daybook = carried
    stream = rolling(1, 4)

    @turn.throw_item!(daybook, at: @there, round: 1, rng: stream)

    assert_equal 4, stream.rand(1..8), "the damage die was not drawn for a doorway"
  end

  # --- the seed -------------------------------------------------------------

  # THE ITEM IS WHICH ROLL OF THE MOMENT IT IS, on `Roll::THROW`'s own axis --
  # which is what keeps a throw off every check, every blow and every toll for
  # ever, none of which pass a `kind` at all.
  test "the die is the one Roll would throw for this thing in this game" do
    daybook = carried
    rng = Roll.generator(story: @story.id, playthrough: @game.id,
                         at: @game.story_now.to_i, sequence: daybook.id, kind: Roll::THROW)

    assert_equal Roll.die(20, rng: rng), @turn.throw_item!(daybook, at: @there, round: 1).check.die
  end

  test "two different things thrown at one story moment are two rolls" do
    things = 12.times.map { |n| carried(name: "thing #{n}") }
    dice = things.map { |thing| Playthrough::Turn.new(@game).throw_item!(thing, at: @there, round: 1).check.die }

    assert_operator dice.uniq.size, :>, 1
  end

  # A CHECK, A BLOW, A TOLL AND A THROW AT ONE MOMENT ARE FOUR DIFFERENT ROLLS,
  # and it is asserted on the SEEDS rather than on the faces: two unrelated d20s
  # agree about one time in twenty, and the property is that the seeds cannot
  # collide AT ALL.
  #
  # THIS IS THE REGRESSION FOR A REAL COLLISION. A throw used to take the
  # NEGATIVE `sequence` space, which was free when it was written and is
  # `Playthrough::Toll`'s the moment hazards landed -- tolls count down from -1,
  # unbounded, so a game that had paid two tolls throwing item #3 seeded the
  # lift and the hazard's save identically. `Roll::THROW` is an axis of its own
  # and cannot be walked onto by anything that counts rows.
  test "a throw shares a seed with no check, no blow and no toll, however many there are" do
    daybook = carried
    at = @game.story_now.to_i
    plain = ->(sequence) { Roll.seed(story: @story.id, playthrough: @game.id, at: at, sequence: sequence) }

    throw_seed = Roll.seed(story: @story.id, playthrough: @game.id, at: at,
                           sequence: daybook.id, kind: Roll::THROW)
    checks = Character::ABILITIES.each_index.map { |index| plain.call(index + 1) }
    blows = 200.times.map { |n| plain.call(Playthrough::Turn::SEQUENCE_OFFSET + n) }
    tolls = 200.times.map { |n| plain.call(-(n + 1)) }

    assert_not_includes checks, throw_seed
    assert_not_includes blows, throw_seed
    assert_not_includes tolls, throw_seed
    assert_operator daybook.id, :>, 0, "and the item id is what makes it a record"
  end

  # The other half of the same property, and the reason the fix is a KIND and not
  # a wider band on `sequence`: it is `Roll::THROW` and not the item id that
  # holds a throw apart. A check, a blow and a toll all pass no kind, so none of
  # them can reach a throw's seed however far it counts -- and item #3's throw is
  # a different die from whatever else `sequence: 3` might one day mean.
  test "it is the kind and not the item id that holds a throw apart" do
    daybook = carried
    at = @game.story_now.to_i
    parts = { story: @story.id, playthrough: @game.id, at: at, sequence: daybook.id }

    assert_not_equal Roll.seed(**parts), Roll.seed(**parts, kind: Roll::THROW)
    assert_equal Roll.seed(**parts, kind: Roll::THROW),
                 @turn.send(:throw_generator, daybook).seed
  end

  # --- the guards -----------------------------------------------------------

  test "a playthrough with no protagonist throws nothing" do
    game = create(:playthrough, story: @story, character: nil, current_location: @here)
    daybook = create(:item, name: "daybook", character: nil, playthrough: game)

    assert_nil Playthrough::Turn.new(game).throw_item!(daybook, at: @rowe, round: 1)
    assert_predicate daybook.reload, :carried?
  end

  test "a body with no abilities has no strength to throw with" do
    @vance.update!(strength: nil, dexterity: nil, will: nil)

    assert_nil @turn.throw_item!(carried, at: @rowe, round: 1)
  end

  test "a throw with nothing to aim at is not a throw" do
    assert_nil @turn.throw_item!(carried, at: nil, round: 1)
  end

  # --- what the narrator is told --------------------------------------------

  # THE FACT IS THE APP'S OWN WORDS ABOUT WHAT ALREADY HAPPENED, exactly
  # `#taken_fact`'s shape. The fumble is the one that most needs saying: nothing
  # moved, so no other record can tell the prose the thing stayed put.
  test "the fumble fact says nothing was thrown and where the thing still is" do
    daybook = carried
    outcome = @turn.throw_item!(daybook, at: @rowe, round: 1, rng: rolling(20))
    fact = @turn.thrown_fact(outcome, @vance)

    assert_match(/NOTHING WAS THROWN/, fact)
    assert_match(/still in the party's hands/, fact)
    assert_match(/turn was spent/, fact)
  end

  test "the fumble fact says where a thing on the floor still is" do
    press = create(:item, :lying, :heavy, name: "strongbox", location: @here, playthrough: @game)
    outcome = @turn.throw_item!(press, at: @rowe, round: 1, rng: rolling(20))

    assert_match(/still lying exactly where it was/, @turn.thrown_fact(outcome, @vance))
  end

  test "the hit fact names the person and puts the thing at their feet" do
    outcome = @turn.throw_item!(carried, at: @rowe, round: 1, rng: rolling(1, 6))
    fact = @turn.thrown_fact(outcome, @vance)

    assert_match(/Halkett Rowe/, fact)
    assert_match(/NO LONGER\s+CARRIED/, fact)
    assert_match(/at Halkett Rowe's feet/, fact)
  end

  # THE NUMBERS ARE DELIBERATELY NOT IN THIS FACT: `Playthrough::Moment#struck_fact`
  # reads the blow out of `playthrough_blows` and already states the damage,
  # whether the body lived, and that the figures do not change. Two facts about
  # one die in one prompt is what this leaves out.
  test "the hit fact leaves the damage to the blow the moment already reports" do
    outcome = @turn.throw_item!(carried, at: @rowe, round: 1, rng: rolling(1, 6))

    assert_no_match(/\b6\b/, @turn.thrown_fact(outcome, @vance))
    assert_match(/struck Halkett Rowe for 6/, Playthrough::Moment.new(@game).struck_fact)
  end

  test "the doorway fact says the thing is no longer in this room" do
    fact = @turn.thrown_fact(@turn.throw_item!(carried, at: @there, round: 1, rng: rolling(1)), @vance)

    assert_match(/The Supply Closet/, fact)
    assert_match(/no longer in this room/, fact)
  end
end
