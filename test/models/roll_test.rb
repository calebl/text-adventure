require "test_helper"

# THE DICE, AND THE ONE PROPERTY THAT MAKES THEM WORTH HAVING.
#
# `Roll` exists so that the same roll comes out the same in any process, after
# any restart, for ever -- the property `WorldMechanic::ShuffleConnections`
# already depends on and the one `rake game:backfill_stat_blocks` promises when
# it prints a dry run. So these tests are mostly about the SEED: that it is
# built from five integers, that each of the five moves it, and that nothing in
# it reaches for anything Ruby salts per process.
class RollTest < ActiveSupport::TestCase
  test "the same four inputs give the same seed" do
    parts = { story: 3, playthrough: 7, at: 1_760_000_000, sequence: 2 }

    assert_equal Roll.seed(**parts), Roll.seed(**parts)
  end

  # Each input has to move the seed on its own, or two different rolls would be
  # one number twice -- which is exactly what `sequence` exists to stop for two
  # people born out of one room realization.
  test "every input moves the seed on its own" do
    base = { story: 3, playthrough: 7, at: 100, sequence: 2, kind: 0 }

    seeds = base.keys.map { |key| Roll.seed(**base.merge(key => base[key] + 1)) }

    assert_equal seeds.uniq.size, seeds.size
    assert_not_includes seeds, Roll.seed(**base)
  end

  # THE TRAP `WorldMechanic::ShuffleConnections` names in its header: Ruby salts
  # `String#hash` per process, so a seed built from one differs after a restart.
  # This is that stated as a test -- the seed is a plain integer expression of
  # its inputs and can be recomputed by hand.
  test "the seed is plain arithmetic and can be recomputed by hand" do
    expected = 3 * Roll::STORY + 7 * Roll::PLAYTHROUGH + 100 * Roll::AT + 2 * Roll::SEQUENCE

    assert_equal expected, Roll.seed(story: 3, playthrough: 7, at: 100, sequence: 2)
  end

  test "a playthrough, a moment, a sequence and a kind all default to zero" do
    assert_equal 5 * Roll::STORY, Roll.seed(story: 5)
  end

  # `kind` DEFAULTING TO ZERO IS A COMPATIBILITY PROMISE, not a convenience:
  # every die this app threw before the axis existed was seeded without one, and
  # a default that moved would re-roll every stat block
  # `rake game:backfill_stat_blocks` and `Story::Repair` can re-derive. This is
  # that promise as an equality between the four-argument call and the five.
  test "a kindless seed is exactly what it was before the kind axis existed" do
    parts = { story: 3, playthrough: 7, at: 100, sequence: 2 }
    by_hand = 3 * Roll::STORY + 7 * Roll::PLAYTHROUGH + 100 * Roll::AT + 2 * Roll::SEQUENCE

    assert_equal by_hand, Roll.seed(**parts)
    assert_equal Roll.seed(**parts), Roll.seed(**parts, kind: 0)
  end

  # AND THE PROPERTY THE AXIS EXISTS FOR: a kind cannot be reached by counting
  # on any other axis, in either direction, however far anything counts. That is
  # what `sequence` could not promise once three sources were carving it up
  # between them -- see `Roll`'s header for the collision that made this
  # necessary.
  test "a kind cannot be cancelled out by any amount of counting elsewhere" do
    thrown = Roll.seed(story: 3, playthrough: 7, at: 100, sequence: 2, kind: Roll::THROW)

    counted = (-500..500).map do |n|
      [ Roll.seed(story: 3, playthrough: 7, at: 100, sequence: n),
        Roll.seed(story: 3, playthrough: 7, at: 100 + n, sequence: 2) ]
    end.flatten

    assert_not_includes counted, thrown
  end

  test "the throw kind is a real, positive kind and not a placeholder" do
    assert_operator Roll::THROW, :>, 0
    assert_not_equal Roll.seed(story: 1, kind: Roll::THROW), Roll.seed(story: 1)
  end

  test "two generators from one seed roll the same sequence of dice" do
    first = Roll.generator(story: 11, sequence: 4)
    second = Roll.generator(story: 11, sequence: 4)

    assert_equal 5.times.map { Roll.die(20, rng: first) },
                 5.times.map { Roll.die(20, rng: second) }
  end

  test "a die is 1..sides and never zero" do
    rng = Roll.generator(story: 1)
    rolls = 500.times.map { Roll.die(6, rng: rng) }

    assert_equal (1..6).to_a, rolls.uniq.sort
  end

  test "one_of draws from the list it is given" do
    rng = Roll.generator(story: 2)
    drawn = 200.times.map { Roll.one_of(Character::HIT_DICE, rng: rng) }

    assert_equal Character::HIT_DICE.sort, drawn.uniq.sort
  end

  # 3d6 IS WHAT AN ABILITY SCORE IS, so a pool of three six-sided dice covers
  # 3..18 and nothing outside it -- which is exactly `Character::ABILITY_RANGE`,
  # and the reason that range is the roll's own bounds rather than a taste.
  test "a pool of 3d6 covers the whole of Character::ABILITY_RANGE and nothing else" do
    rng = Roll.generator(story: 9)
    rolls = 5_000.times.map { Roll.pool(3, 6, rng: rng) }

    assert_equal Character::ABILITY_RANGE.to_a, rolls.uniq.sort
  end

  # A pool is the sum of its dice off ONE generator, in order -- written out here
  # against three separate `#die` calls on a second generator built from the
  # same seed, which is the same sequence of draws by hand.
  test "a pool is the sum of its dice, drawn in order from the generator it is handed" do
    by_hand = 3.times.sum { Roll.die(6, rng: @same ||= Roll.generator(story: 4, sequence: 1)) }

    assert_equal by_hand, Roll.pool(3, 6, rng: Roll.generator(story: 4, sequence: 1))
  end

  # THE ORDER OF THE DRAWS IS THE ANSWER, which is what `Character::StatBlock`'s
  # header says must not be tidied: a pool takes its dice from the generator it
  # is handed, in sequence, so the draws after it see the generator advanced.
  test "a pool advances the generator by one draw per die" do
    one = Roll.generator(story: 6, sequence: 3)
    other = Roll.generator(story: 6, sequence: 3)

    Roll.pool(3, 6, rng: one)
    3.times { Roll.die(6, rng: other) }

    assert_equal Roll.die(20, rng: one), Roll.die(20, rng: other)
  end

  test "a pool of no dice is refused rather than answering zero" do
    assert_raises(ArgumentError) { Roll.pool(0, 6, rng: Roll.generator(story: 1)) }
  end

  test "one_of refuses an empty list rather than answering nil" do
    assert_raises(ArgumentError) { Roll.one_of([], rng: Roll.generator(story: 1)) }
  end
end
