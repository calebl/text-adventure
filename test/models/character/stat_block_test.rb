require "test_helper"

# WHERE A STAT BLOCK COMES FROM, and the one property the whole thing stands on:
# the same four inputs give the same five numbers, in any process, for ever.
#
# THE ORDER OF THE DRAWS IS WHAT IS PINNED HERE. `Roll.generator` is handed
# around rather than kept precisely so a caller throwing several dice for one
# decision throws them from one seed in one order, and this roll's order --
# the hit die, then `Character::ABILITIES` in its stated order -- is what makes
# a body re-derivable. Reordering either list re-rolls every body
# `rake game:backfill_stat_blocks` would ever write, which is why it is a test
# and not a comment.
class Character::StatBlockTest < ActiveSupport::TestCase
  test "a roll answers exactly the five columns, and no others" do
    rolled = Character::StatBlock.roll(story: 3, sequence: 1)

    assert_equal [ :level, :hit_die, *Character::ABILITIES ], rolled.keys
  end

  test "every body starts at level one, which is not a roll" do
    5.times { |n| assert_equal 1, Character::StatBlock.roll(story: 3, sequence: n)[:level] }
  end

  test "the hit die is one of the three the engine draws from" do
    dice = 60.times.map { |n| Character::StatBlock.roll(story: 3, sequence: n)[:hit_die] }

    assert_equal Character::HIT_DICE.sort, dice.uniq.sort
  end

  test "every ability is inside the range 3d6 rolls" do
    200.times do |n|
      rolled = Character::StatBlock.roll(story: 7, sequence: n)
      Character::ABILITIES.each { |ability| assert_includes Character::ABILITY_RANGE, rolled[ability] }
    end
  end

  # THE DRAWS, IN THE STATED ORDER, RECOMPUTED BY HAND off a generator built from
  # the same seed: `Roll.one_of(HIT_DICE)` first, then one `Roll.pool(3, 6)` per
  # ability in `Character::ABILITIES` order. If this fails, the roll's order has
  # moved and every derived body in every database has moved with it.
  test "the draws come off one generator in the order the header states" do
    rng = Roll.generator(story: 11, at: 500, sequence: 4)
    expected = { level: 1, hit_die: Roll.one_of(Character::HIT_DICE, rng: rng) }
    Character::ABILITIES.each { |ability| expected[ability] = Roll.pool(3, 6, rng: rng) }

    assert_equal expected, Character::StatBlock.roll(story: 11, at: 500, sequence: 4)
  end

  # The abilities are three separate draws rather than one number three times,
  # which is what `sequence` exists to guarantee one level up and what handing
  # ONE generator around guarantees here.
  test "the three abilities are three draws and not one number repeated" do
    spreads = 40.times.map do |n|
      Character::StatBlock.roll(story: 5, sequence: n).values_at(*Character::ABILITIES)
    end

    assert spreads.any? { |scores| scores.uniq.size == Character::ABILITIES.size }
  end

  test "the same four inputs give the same five numbers" do
    parts = { story: 2, at: 1_760_000_000, sequence: 6 }

    assert_equal Character::StatBlock.roll(**parts), Character::StatBlock.roll(**parts)
  end

  # WHAT MAKES A DRY RUN WORTH ANYTHING, one layer down from
  # `Character::StatBackfill`: an existing row is keyed on its own id, so the
  # numbers a rehearsal printed are the numbers the real run writes.
  test "an existing row's body is keyed on the story and the row's own id" do
    story = create(:story)
    character = create(:character, story: story)

    assert_equal Character::StatBlock.roll(story: story.id, sequence: character.id),
                 Character::StatBlock.for_existing(character)
  end

  test "two rows in one story get different bodies" do
    story = create(:story)
    one = create(:character, story: story)
    other = create(:character, story: story)

    assert_not_equal Character::StatBlock.for_existing(one), Character::StatBlock.for_existing(other)
  end
end
