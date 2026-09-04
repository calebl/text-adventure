require "test_helper"

# THE DICE, AND THE ONE PROPERTY THAT MAKES THEM WORTH HAVING.
#
# `Roll` exists so that the same roll comes out the same in any process, after
# any restart, for ever -- the property `WorldMechanic::ShuffleConnections`
# already depends on and the one `rake game:backfill_stat_blocks` promises when
# it prints a dry run. So these tests are mostly about the SEED: that it is
# built from four integers, that each of the four moves it, and that nothing in
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
    base = { story: 3, playthrough: 7, at: 100, sequence: 2 }

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

  test "a playthrough, a moment and a sequence all default to zero" do
    assert_equal 5 * Roll::STORY, Roll.seed(story: 5)
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

  test "one_of refuses an empty list rather than answering nil" do
    assert_raises(ArgumentError) { Roll.one_of([], rng: Roll.generator(story: 1)) }
  end
end
