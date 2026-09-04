require "test_helper"

# ZERO HIT POINTS MEANS DEATH, AND DEATH ENDS THE PLAYTHROUGH.
#
# The captain's ruling of 2026-09-04, verbatim: *"zero hit points means death.
# Playthrough is over and you can't do anything else. You have to start a new
# playthrough. Eventually, we can add going back to saved previous state."*
#
# `lib/engine_sweep/scripts/death-ends-a-playthrough.yml` walks the ruling
# through the engine one typed line at a time; these are the statements
# underneath it -- the transition itself, what it costs (nothing), and the two
# doors it must be in front of.
class Playthrough::DeathTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @room = create(:location, story: @story)
    @vance = create(:character, :protagonist, story: @story, fullname: "Odile Vance",
                                              level: 1, hit_die: 6)
    @rowe = create(:character, story: @story, fullname: "Halkett Rowe", location: @room,
                              level: 1, hit_die: 8)
    @game = create(:playthrough, story: @story, character: @vance, current_location: @room)
    @turn = Playthrough::Turn.new(@game)
  end

  # --- the transition --------------------------------------------------------

  test "taking the last hit point off the player ends the playthrough" do
    assert_not @game.over?

    @turn.harm!(@vance, 6)

    assert @game.over?
    assert @game.reload.ended_at.present?
  end

  # A harm that would overshoot stops at zero: "how far past dead" is a number
  # this game has no use for, because there are no death saves and no scars.
  test "a harm past zero stops at zero" do
    assert_equal 0, @turn.harm!(@vance, 99).hp
  end

  # STORY TIME, NOT THE WALL CLOCK. A death rehearsed from a backup must not be
  # dated to whenever the backup was opened.
  test "the ending is stamped on the story's clock" do
    @turn.harm!(@vance, 6)

    assert_equal @game.story_now.to_i, @game.reload.ended_at.to_i
  end

  test "the moment a game ended is never re-dated" do
    @turn.harm!(@vance, 6)
    was = @game.reload.ended_at

    @game.end!(at: 1.year.from_now)

    assert_equal was.to_i, @game.reload.ended_at.to_i
  end

  # KILLING AN NPC IS NOT THE END OF ANYTHING. The ruling is about the player's
  # body, and `harm!` reads which body it was handed.
  test "an NPC reaching zero does not end the playthrough" do
    @turn.harm!(@rowe, 8)

    assert_equal 0, @game.vitals_for(@rowe).hp
    assert_not @game.over?
  end

  test "a mend never raises the dead" do
    @turn.harm!(@vance, 6)

    assert_equal 0, @turn.mend!(@vance, 6).hp
    assert @game.over?
  end

  test "a mend stops at the maximum the stat block allows" do
    @turn.harm!(@vance, 2)

    assert_equal 6, @turn.mend!(@vance, 99).hp
  end

  test "there is nothing to harm on somebody with no stat block" do
    nobody = create(:character, :without_a_stat_block, story: @story, location: @room)

    assert_nil @turn.harm!(nobody, 3)
    assert_nil @turn.mend!(nobody, 3)
  end

  # --- what a line costs afterwards ------------------------------------------

  # THE GATE IS IN FRONT OF THE CLASSIFIER, which is what makes a line typed
  # into a finished game free. `EngineSweep` proves the same thing for the
  # mechanics mode by replacing `BaseAgent.new`; this proves it for the browser
  # loop, where the classifier is the one call every turn makes.
  test "a line typed into a dead playthrough makes no model call" do
    @turn.harm!(@vance, 6)

    Playthrough::Classifier.stub :new, ->(*) { raise "the classifier was reached" } do
      refusal = @turn.play("go north")

      assert_instance_of Playthrough::Refusal, refusal
      assert_equal :dead, refusal.kind
    end
  end

  test "a line typed into a dead playthrough writes nothing" do
    @turn.harm!(@vance, 6)
    before = [ Scene.count, Item.count, @game.current_location_id, @story.clock ]

    @turn.play("take the ward stamp")

    assert_equal before, [ Scene.count, Item.count, @game.reload.current_location_id, @story.reload.clock ]
  end

  test "the refusal names the player and offers a new playthrough" do
    @turn.harm!(@vance, 6)
    refusal = @turn.play("look around")

    assert_match(/Odile Vance is dead/, refusal.text)
    assert_match(/new playthrough/, refusal.text)
    assert_equal "look around", refusal.typed
  end

  # THE SECOND DOOR. `rake game:mechanics` reaches the engine without going
  # through `Playthrough::Turn#play` at all, so the gate has to be in front of
  # its dispatch too -- and it reads the same `Playthrough::Refusal`, so the two
  # modes cannot come to disagree about whether a game is over.
  test "the mechanics mode refuses a dead playthrough in the same words" do
    @turn.harm!(@vance, 6)
    report = Playthrough::Mechanics.new(@game, model: false).run("look")

    assert report.refused?
    assert_not report.changed?
    assert_match(/Odile Vance is dead/, report.refusal)
    assert report.state.over
  end

  # --- one game ending is one game ending ------------------------------------

  test "one playthrough ending leaves another playthrough of the same world running" do
    other = create(:playthrough, story: @story, character: @vance, current_location: @room)

    @turn.harm!(@vance, 6)

    assert @game.over?
    assert_not other.reload.over?
    assert_equal 6, other.vitals_for(@vance).hp
  end
end
