require "test_helper"

# A PLAYTHROUGH WITH NOBODY PLAYING IT, AND WHAT THE ENGINE DOES WITH ONE.
#
# THE CAPTAIN'S REPORT, 2026-09-05, on his playthrough 24, in his words:
#
#   *"I just picked up a signet ring and a key. The narration was perfect. But
#   the machinery and debug view do not show me carrying the items. They are
#   still lying on the floor."*
#
# The story he was playing had no character marked `is_protagonist`, so
# `Playthrough#character` was nil. `Playthrough::Turn#take_item` answered that
# by handing `Scene::Narrator` the bare command with no fact under it -- the
# model was asked to narrate "take iron key" and did it beautifully -- and the
# item's row never moved. The narration lied and the records were honest, which
# is the one direction this app is built not to fail in.
#
# Every test here is the same statement in a different act: the line is REFUSED
# (`Playthrough::Refusal`'s `:unplayable`), no row moves, no `Scene` is written,
# and NO MODEL IS ASKED ANYTHING. The last is asserted the way `EngineSweep`
# asserts it -- `BaseAgent.new` is replaced by something that raises -- because
# the defect was a model call that should never have been made.
class Playthrough::TurnNoProtagonistTest < ActiveSupport::TestCase
  class ModelCalled < StandardError; end

  def setup
    @story = create(:story)
    @here = create(:location, story: @story, name: "Ward Office 12")
    @there = create(:location, story: @story, name: "The Supply Closet")
    create(:location_connection, location: @here, connected_location: @there)
    create(:location_connection, location: @there, connected_location: @here)
    @game = create(:playthrough, story: @story, character: nil, current_location: @here)
    @turn = Playthrough::Turn.new(@game)
  end

  # The sweep's guard, in one file: a model call anywhere under the block is a
  # failure and not a slow test.
  def with_no_model
    BaseAgent.stub(:new, ->(*, **) { raise ModelCalled, "the engine asked a model about a line it cannot play" }) do
      yield
    end
  end

  # Lying in the room, in THIS game's layer -- the only layer play reads.
  def lying_here(name)
    create(:item, name: name, location: @here, character: nil, playthrough: @game)
  end

  def carried(name)
    create(:item, name: name, location: nil, character: nil, playthrough: @game)
  end

  test "a take is refused, the item stays on the floor and no model is asked" do
    ring = lying_here("prince's signet ring")

    outcome = with_no_model { @turn.play("/take prince's signet ring") }

    assert_kind_of Playthrough::Refusal, outcome
    assert_equal :unplayable, outcome.kind
    assert_match "no player character yet", outcome.text
    assert_match "Nothing has changed.", outcome.text

    ring.reload
    assert_equal @here, ring.location, "the ring never left the floor"
    assert_nil ring.character
    assert_empty @game.carried
  end

  test "a refused take writes no Scene and does not move the story's clock" do
    lying_here("iron key")
    before = @story.reload.clock

    assert_no_difference -> { @story.scenes.count } do
      with_no_model { @turn.play("/take iron key") }
    end

    assert_equal before, @story.reload.clock
  end

  # THE DEFECT'S OTHER HALF. The turn used to be recorded as a `take` that acted
  # on no record at all -- `resolved_action: "take", acted_on: nil` -- which is
  # what the captain's debug view was reading when it disagreed with the prose.
  # There is no row to disagree with now.
  test "a refused take records no transition, because there was no turn" do
    lying_here("iron key")

    with_no_model { @turn.play("/take iron key") }

    assert_nil @story.scenes.where(resolved_action: "take").first
  end

  test "a throw is refused with nobody to throw it" do
    slate = carried("tide slate")

    outcome = with_no_model { @turn.play("/throw tide slate at The Supply Closet") }

    assert_kind_of Playthrough::Refusal, outcome
    assert_equal :unplayable, outcome.kind
    assert_match "nobody here to throw anything", outcome.text

    slate.reload
    assert_nil slate.location, "the slate never left the party's hands"
    assert_empty @game.blows
  end

  # THE OTHER MISSING RECORD, and it is a different one: a playthrough standing
  # in no room has no floor to put anything down on. `#drop_item` carried the
  # same "nothing in the app produces one" comment and the same narrated
  # attempt.
  test "a drop is refused by a playthrough standing nowhere" do
    nowhere = create(:playthrough, story: @story, character: nil, current_location: nil)
    slate = create(:item, name: "tide slate", location: nil, character: nil, playthrough: nowhere)

    outcome = with_no_model { Playthrough::Turn.new(nowhere).play("/drop tide slate") }

    assert_kind_of Playthrough::Refusal, outcome
    assert_equal :unplayable, outcome.kind
    assert_match "standing nowhere", outcome.text

    slate.reload
    assert_nil slate.location
    assert_equal [ slate ], nowhere.carried.to_a
  end

  # WHAT IS NOT REFUSED BY THIS. A game with no protagonist can still be walked
  # around and looked at: the refusal is about the two acts that need a pair of
  # hands and the one that needs a floor, and widening it would refuse a whole
  # game rather than the lines it cannot play. `PlaythroughsController#create`
  # is what stops such a game being started in the first place.
  test "a line that needs no hands is not refused" do
    outcome = Playthrough::Refusal.unplayable(
      Playthrough::Classifier::Intent.new(action: :examine, item: lying_here("iron key")),
      playthrough: @game, typed: "read iron key"
    )

    assert_nil outcome
  end

  # AND THE READING IS ANSWERED BEFORE THE GAME IS. "take the sky" resolved to
  # nothing, and answering it with "there is nobody here to pick anything up"
  # would name the wrong defect. Walked through `Playthrough::Mechanics` with
  # `model: false`, which is the one reader that answers every line offline --
  # `Playthrough::Grammar#reading_first` hands an unresolved noun to the
  # classifier by design, which is a model call this test will not make.
  test "a take that resolved to nothing is still refused as drift and not as a missing player" do
    lying_here("iron key")

    report = with_no_model { Playthrough::Mechanics.new(@game, model: false).run("take the sky") }

    assert_match(/no thing lying here called/, report.refusal)
    assert_no_match(/no player character/, report.refusal)
  end

  # AND THE TWO MODES SAY THE SAME THING ABOUT THE SAME LINE, which is the rule
  # `Playthrough::Refusal` exists for. `rake game:mechanics` already refused this
  # take, in words of its own; the browser narrated it. They are one sentence
  # now.
  test "the mechanics mode refuses the take in the engine's own words" do
    lying_here("iron key")

    report = with_no_model { Playthrough::Mechanics.new(@game, model: false).run("take iron key") }

    assert_match "no player character yet", report.refusal
    assert_equal @here, Item.find_by(name: "iron key").location
  end
end
