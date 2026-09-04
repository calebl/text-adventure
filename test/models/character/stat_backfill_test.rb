require "test_helper"

# A BODY FOR EVERYBODY WHO WAS WRITTEN BEFORE THERE WERE BODIES.
#
# It is the one backfill in this app that DECIDES rather than recovers, so what
# these pin is the two properties that make deciding acceptable: it is
# deterministic, so a dry run and the real run agree, and it never touches
# somebody who already has an answer.
class Character::StatBackfillTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @with = create(:character, story: @story, level: 1, hit_die: 10)
    @without = create(:character, :without_a_stat_block, story: @story)
  end

  def backfill = Character::StatBackfill.new(@story)

  test "it rolls a body for somebody who has none" do
    answers = backfill.run

    assert_equal [ @without ], answers.map(&:character)
    assert @without.reload.stat_block?
    assert_includes Character::HIT_DICE, @without.hit_die
    assert_equal 1, @without.level
  end

  # THE RECORDS WIN OVER A DERIVATION, which is the rule everywhere in this app.
  test "it never re-rolls somebody who already has one" do
    backfill.run

    assert_equal [ 1, 10 ], [ @with.reload.level, @with.hit_die ]
  end

  test "a dry run writes nothing and reports what it would have written" do
    answers = backfill.run(dry_run: true)

    assert_equal 1, answers.size
    assert_not @without.reload.stat_block?
  end

  # WHAT MAKES A DRY RUN WORTH ANYTHING. `Roll` seeds on the story and the
  # character id through plain arithmetic, so the number the rehearsal printed
  # is the number the real run writes -- in this process and in any other.
  test "the dry run's numbers are the numbers the real run writes" do
    rehearsed = backfill.run(dry_run: true).first

    written = backfill.run.first

    assert_equal rehearsed.rolled, written.rolled
    assert_equal written.rolled[:hit_die], @without.reload.hit_die
  end

  test "it is idempotent" do
    backfill.run

    assert_empty backfill.run
  end

  # `Character#a_stat_block_is_whole` refuses to save one, so a half block can
  # only arrive through raw SQL -- and rolling both columns is the only way to
  # make it whole without inventing a partner for the half that is there.
  test "half a stat block is a candidate too" do
    Character.where(id: @with.id).update_all(hit_die: nil)

    assert_equal [ @with, @without ].map(&:id).sort, backfill.candidates.map(&:id).sort
  end

  # The report a person reads: what the body will hold, not only what it is
  # made of.
  test "an answer states the maximum the rolled body can hold" do
    answer = backfill.run.first

    assert_equal answer.hit_die, answer.max_hp
    assert_match(/level 1, d#{answer.hit_die} \(#{answer.max_hp} hp\)/, answer.to_s)
  end
end
