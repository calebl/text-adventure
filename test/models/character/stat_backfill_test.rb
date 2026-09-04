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

  # --- the three abilities ---------------------------------------------------
  #
  # A body is five columns since the captain's ruling of 2026-09-04 evening, and
  # the candidate set is "missing any of the five".

  test "somebody with a body and no abilities is a candidate, and gets only the abilities" do
    @with.update!(strength: nil, dexterity: nil, will: nil)

    answers = backfill.run

    assert_includes answers.map(&:character), @with
    assert_predicate @with.reload, :abilities?
    assert_equal [ 1, 10 ], [ @with.level, @with.hit_die ], "the records win over a derivation"
  end

  # THE RECORDS WIN OVER A DERIVATION, one column-set over: a hand-authored hit
  # die must survive a run that only had to fill in the abilities. This is what
  # lets `bin/update` run over a seeded world without moving what the file says.
  test "it fills only the columns that were empty" do
    @with.update!(will: nil, strength: nil, dexterity: nil)

    answer = backfill.run.find { |candidate| candidate.character == @with }

    assert_equal Character::ABILITIES, answer.filled.keys
    assert_not answer.body?
    assert_predicate answer, :abilities?
  end

  test "a partial set of abilities is a candidate too" do
    Character.where(id: @with.id).update_all(dexterity: nil)

    assert_includes backfill.candidates, @with

    backfill.run

    assert_predicate @with.reload, :abilities?
  end

  test "a whole sheet is left alone and the run is still idempotent" do
    backfill.run

    assert_empty backfill.run
    assert_equal [ 1, 10, 12, 10, 14 ],
                 [ @with.reload.level, @with.hit_die, @with.strength, @with.dexterity, @with.will ]
  end

  # Somebody with nothing at all -- the state every character in a database
  # older than both migrations is in.
  test "a character with no sheet at all gets the whole of one" do
    nobody = create(:character, :without_a_sheet, story: @story)

    backfill.run

    assert_predicate nobody.reload, :stat_block?
    assert_predicate nobody, :abilities?
  end

  test "an answer names the abilities it rolled" do
    nobody = create(:character, :without_a_sheet, story: @story)

    answer = backfill.run.find { |candidate| candidate.character == nobody }

    assert_match(/strength #{nobody.reload.strength} dexterity #{nobody.dexterity} will #{nobody.will}/, answer.to_s)
  end
end
