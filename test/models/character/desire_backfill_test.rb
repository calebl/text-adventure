require "test_helper"

# THE BACKFILL, AND THE ONE THING IT MUST NOT DO: WRITE WHEN NOBODY ASKED IT TO.
#
# `rake game:backfill_stat_blocks` is dry on `DRY_RUN=1` because a rehearsal
# and the write produce identical numbers. This one asks a model, so a
# rehearsal can only ever be an EXAMPLE of the answer -- which is why it is dry
# by default and these tests are about the default.
class Character::DesireBackfillTest < ActiveSupport::TestCase
  setup do
    @story = create(:story)
    @waiting = create(:character, :without_desires, story: @story, fullname: "Perrin Lasco")
    @already = create(:character, story: @story, fullname: "Odile Vance")
  end

  # A stand-in for the one model call, so the test is about the backfill rather
  # than about a provider. The real writer is `Character::DesireWriter`.
  ANSWER = { desires: { conscious_desire: "Perrin wants the index into somebody's hands",
                        unconscious_desire: "Perrin wants his name said out loud",
                        recognized_need: "Perrin needs to write everything down twice",
                        unrecognized_need: "Perrin needs to ask for something for himself" },
             pursuits: { desire_pursuit: "offer", need_pursuit: "attend" } }.freeze

  def with_a_writer(answering: -> { ANSWER })
    writer = Object.new
    writer.define_singleton_method(:generate) { answering.call }
    Character::DesireWriter.stub(:new, ->(_character) { writer }) { yield }
  end

  test "only people with none of the four are pending" do
    assert_equal [ @waiting ], Character::DesireBackfill.new(@story).pending
  end

  test "a dry run writes nothing at all" do
    with_a_writer do
      answers = Character::DesireBackfill.new(@story).run(dry_run: true)

      assert_equal 1, answers.size
      assert_not answers.first.written
    end

    assert_nil @waiting.reload.conscious_desire
    assert_not_predicate @waiting, :desires?
  end

  test "a dry run still shows what it would have written" do
    with_a_writer do
      answer = Character::DesireBackfill.new(@story).run(dry_run: true).first

      assert_equal "offer", answer.pursuits[:desire_pursuit]
      assert_includes answer.to_s, "Perrin Lasco"
    end
  end

  test "writing keeps the answer and leaves everybody who already had one alone" do
    before = @already.conscious_desire

    with_a_writer do
      answers = Character::DesireBackfill.new(@story).run(dry_run: false)

      assert answers.first.written
    end

    assert_predicate @waiting.reload, :desires?
    assert_equal "offer", @waiting.desire_pursuit
    assert_equal before, @already.reload.conscious_desire
  end

  test "a refusal is dropped with its reason rather than raised" do
    with_a_writer(answering: -> { raise BaseAgent::RefusalError, "the model declined" }) do
      answer = Character::DesireBackfill.new(@story).run(dry_run: false).first

      assert_not answer.written
      assert_includes answer.note, "the model declined"
    end

    assert_not_predicate @waiting.reload, :desires?
  end
end
