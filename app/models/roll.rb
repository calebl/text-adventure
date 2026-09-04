# THE DICE, AND THE SEED THEY ARE THROWN FROM.
#
# WHY IT EXISTS AT ALL: *"A model cannot set an NPC's numbers, the engine rolls
# them"* -- the captain's ruling of 2026-09-04. Every number on a stat block is
# thrown here, so there is exactly one place in the app where a die is rolled
# and exactly one place a seed is built.
#
# DETERMINISM IS LOAD-BEARING, and the precedent is
# `WorldMechanic::ShuffleConnections`: the same turn has to roll the same die in
# any process, after any restart, for ever, or `rake game:sweep` cannot assert a
# number and `rake game:doctor` cannot re-derive one it repaired last week.
#
# NOTE WHAT IS NOT USED TO BUILD A SEED. `String#hash` and `Array#hash` are
# SALTED PER PROCESS in Ruby, so seeding from either would make the same roll
# come out differently after a restart -- the exact property this module exists
# to have. Every input is an integer and the arithmetic is plain, which is the
# rule `ShuffleConnections#seed_for` already keeps and the one thing about this
# file that must not be "simplified".
#
# WHAT A SEED IS MADE OF -- four integers, each of which answers a different
# "which roll is this":
#
#   story        which world. Two worlds do not share a die.
#   playthrough  which game, `0` when the roll belongs to the world itself
#                rather than to somebody playing it (a stat block is world data,
#                so the registry rolls with 0 and every game reads the same
#                person).
#   at           where the STORY's clock stood, in seconds. Story time, never
#                the wall clock -- a roll seeded from `Time.current` would come
#                out differently every time the same repair was rehearsed.
#   sequence     which roll within that moment. Two people born out of one room
#                realization are two rolls, and without this they would be one
#                number twice.
#
# THE PRIMES are odd and pairwise distinct so that the four inputs cannot cancel
# each other out: incrementing `sequence` by one and `at` by one must not land
# on the seed some other pair would.
module Roll
  STORY = 1_000_003
  PLAYTHROUGH = 100_003
  AT = 10_007
  SEQUENCE = 1_009

  # THE SEED, FROM FOUR INTEGERS AND NOTHING ELSE. Public because it is the part
  # worth asserting on its own: `RollTest` pins that the same four inputs give
  # the same seed and that nudging any one of them changes it.
  def self.seed(story:, playthrough: 0, at: 0, sequence: 0)
    story.to_i * STORY + playthrough.to_i * PLAYTHROUGH + at.to_i * AT + sequence.to_i * SEQUENCE
  end

  # A generator for one roll. Handed around rather than kept, so a caller
  # throwing several dice for one decision throws them from one seed in one
  # order, and a test can hand in a `Random` of its own.
  def self.generator(**seed_parts)
    Random.new(seed(**seed_parts))
  end

  # ONE DIE. `sides` is the die's face count -- 6, 8, 10 -- and the result is
  # 1..sides, which is what a die is.
  def self.die(sides, rng:)
    rng.rand(1..sides.to_i)
  end

  # THREE DICE ADDED, which is what an ability score is: `pool(3, 6, rng:)` is
  # the 3d6 `Character::StatBlock` draws a strength, a dexterity and a will
  # from. It is here rather than in the caller for the same reason `#one_of` is
  # -- one place in the app throws a die -- and it draws from the generator it
  # is handed, so three ability scores rolled for one body come out of one seed
  # in one order.
  def self.pool(count, sides, rng:)
    count = count.to_i
    raise ArgumentError, "a pool is at least one die" if count < 1

    count.times.sum { die(sides, rng: rng) }
  end

  # ONE OF A CLOSED LIST, drawn from the same generator. This is how the engine
  # decides which hit die a body has: the list is `Character::HIT_DICE`, the
  # choice is a roll, and no model is asked.
  def self.one_of(choices, rng:)
    choices = Array(choices)
    raise ArgumentError, "nothing to choose from" if choices.empty?

    choices[rng.rand(choices.size)]
  end
end
