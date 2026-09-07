require "test_helper"

# ONE BEAT OF THE ARC, REACHED, IN ONE GAME -- the `Item` layer split applied to
# progress. What these pin is the split and the idempotence the unique index
# buys: the arc is evaluated on every turn, so a beat that wrote a row a turn
# would fill the table from one room.
class Playthrough::BeatTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @quest = create(:quest, story: @story)
    @step = create(:quest_step, quest: @quest, position: 1)
    @game = create(:playthrough, story: @story)
  end

  test "reaching a beat twice is one row, and keeps the first moment" do
    first = Playthrough::Beat.reach!(@game, @step, at: @story.start_time)
    again = Playthrough::Beat.reach!(@game, @step, at: @story.start_time + 2.hours)

    assert_equal first, again
    assert_equal @story.start_time, again.reload.reached_at
    assert_equal 1, Playthrough::Beat.count
  end

  test "two games reach the same beat separately" do
    second = create(:playthrough, story: @story)

    Playthrough::Beat.reach!(@game, @step, at: @story.start_time)
    Playthrough::Beat.reach!(second, @step, at: @story.start_time)

    assert_equal 2, Playthrough::Beat.count
  end

  test "a beat pointing at another story's arc is refused" do
    elsewhere = create(:quest_step, quest: create(:quest, story: create(:story)))

    assert_not build(:playthrough_beat, playthrough: @game, quest_step: elsewhere).valid?
  end

  test "destroying a playthrough takes its beats and leaves the arc" do
    Playthrough::Beat.reach!(@game, @step, at: @story.start_time)

    assert_difference "Playthrough::Beat.count", -1 do
      assert_no_difference "Quest::Step.count" do
        @game.destroy
      end
    end
  end
end
