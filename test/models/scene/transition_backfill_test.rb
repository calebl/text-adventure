require "test_helper"

# LABELLING WHAT WAS PLAYED BEFORE THE COLUMNS EXISTED, out of the classifier's
# own stored answer -- and, more importantly, REFUSING TO where the answer
# cannot be turned back into a record.
#
# The point of the whole instrument is that `Scene#resolved_action` and
# `Scene#acted_on` mean exactly what they say. A backfill that guessed would
# put a wrong transition under a real narration and every check reading one
# would inherit the guess, so the three outcomes are told apart and the third
# writes nothing at all. See `Scene::TransitionBackfill`.
class Scene::TransitionBackfillTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @protagonist = create(:character, story: @story, fullname: "Iri Calder", is_protagonist: true)
    @here = create(:location, story: @story, name: "Ashgate Market")
    @playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
    @chat = create(:chat, playthrough: @playthrough, purpose: "classifier")
  end

  # A turn as it stood before the columns: prose, a typed line, and the
  # classifier's structured answer filed against it by `BaseAgent#attribute_to!`.
  def old_turn(answer, location: @here)
    scene = create(:scene, story: @story, location: location, typed: "a line somebody typed")
    create(:message, :assistant, chat: @chat, scene: scene, content: "", content_raw: answer)
    scene
  end

  def backfill(dry_run: false) = Scene::TransitionBackfill.new(@story).run(dry_run: dry_run)

  test "a take is labelled with the action and the item it moved" do
    key = create(:item, :lying, location: @here, name: "Brass Key")
    scene = old_turn({ "intent" => "take", "target" => "Brass Key" })

    assert_equal({ labelled: 1 }, backfill.slice(:labelled))
    assert_equal "take", scene.reload.resolved_action
    assert_equal key, scene.acted_on
    assert_predicate scene, :took?
  end

  test "a move is labelled with the room and a talk with the person" do
    there = create(:location, story: @story, name: "The Long Hallway")
    maren = create(:character, story: @story, fullname: "Maren Vosk", nickname: "Vosk")

    moved = old_turn({ "intent" => "move", "target" => "The Long Hallway" })
    talked = old_turn({ "intent" => "talk", "target" => "Vosk" })

    backfill

    assert_equal there, moved.reload.acted_on
    assert_equal maren, talked.reload.acted_on
  end

  # A REACH THAT FOUND NOTHING IS A FACT ABOUT THAT TURN, not a gap: the action
  # is written and the record is left nil, which is what the turn really was.
  test "an answer of nothing is labelled with the action and no record" do
    scene = old_turn({ "intent" => "move", "target" => "nothing" })

    assert_equal({ drifted: 1 }, backfill.slice(:drifted))
    assert_equal "move", scene.reload.resolved_action
    assert_nil scene.acted_on
  end

  # THE ONE THAT MATTERS. A named target the records no longer have would become
  # an action with no record -- which reads as drift to `Scene#took?` and to the
  # sweep, so labelling it that way would manufacture a drift the game never
  # had. Nothing is written; a blank column says "not known".
  test "a named target the records no longer have is left blank rather than guessed" do
    scene = old_turn({ "intent" => "take", "target" => "Brass Key" })

    assert_equal({ unrecoverable: 1 }, backfill.slice(:unrecoverable))
    assert_nil scene.reload.resolved_action
    assert_nil scene.acted_on
  end

  # A name two rows answer to cannot say which one it meant, on the same rule
  # `Story::Audit#place_names` follows.
  test "a name two records share is left blank" do
    create(:item, :lying, location: @here, name: "Brass Key")
    create(:item, :lying, location: create(:location, story: @story), name: "Brass Key")
    scene = old_turn({ "intent" => "take", "target" => "Brass Key" })

    assert_equal({ unrecoverable: 1 }, backfill.slice(:unrecoverable))
    assert_nil scene.reload.resolved_action
  end

  # The conversation is what this reads, and `Chat::KEEP_TURNS` can still be
  # asked to throw it away. A turn whose exchange is gone stays blank.
  test "a turn whose classifier exchange was pruned stays blank" do
    scene = create(:scene, story: @story, location: @here, typed: "a line somebody typed")

    assert_equal({ unrecoverable: 1 }, backfill.slice(:unrecoverable))
    assert_nil scene.reload.resolved_action
  end

  # The opening arrival is world data written before anybody played, so it did
  # nothing and has no exchange to read.
  test "the opening arrival is not counted and not labelled" do
    opening = create(:scene, :opening, story: @story, location: @here)

    assert_equal 0, backfill.values.sum
    assert_nil opening.reload.resolved_action
  end

  test "a turn already carrying what it did is left alone" do
    key = create(:item, :lying, location: @here, name: "Brass Key")
    scene = create(:scene, story: @story, location: @here, resolved_action: "drop", acted_on: key)

    assert_equal 0, backfill.values.sum
    assert_equal "drop", scene.reload.resolved_action
  end

  test "a dry run counts everything and writes nothing" do
    create(:item, :lying, location: @here, name: "Brass Key")
    scene = old_turn({ "intent" => "take", "target" => "Brass Key" })

    assert_equal({ labelled: 1 }, backfill(dry_run: true).slice(:labelled))
    assert_nil scene.reload.resolved_action
  end

  test "it calls no model and needs no key" do
    create(:item, :lying, location: @here, name: "Brass Key")
    old_turn({ "intent" => "take", "target" => "Brass Key" })

    BaseAgent.stub(:new, ->(*) { raise "the backfill must not call a model" }) do
      assert_equal 1, backfill[:labelled]
    end
  end
end
