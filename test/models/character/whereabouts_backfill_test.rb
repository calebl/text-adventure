require "test_helper"

# The one-time recovery: where somebody was, out of the only record that ever
# held it. What it refuses to do is the half worth testing -- a person cannot be
# in two rooms, so a backfill that picked one would be inventing which.
class Character::WhereaboutsBackfillTest < ActiveSupport::TestCase
  def setup
    @story = create(:story, start_time: Time.utc(2026, 9, 1, 5, 20))
    @office = create(:location, story: @story, name: "Ward Office 12")
    @closet = create(:location, story: @story, name: "The Supply Closet")
  end

  # A scene with NO story time is a real shape an older database holds --
  # `Story::Doctor#scene_rows` reports them -- but `Scene` validates the column,
  # so it is written the only way one can exist.
  def scene_in(location, at:, cast:)
    scene = create(:scene, story: @story, location: location,
                           story_timestamp: at || 1.hour.ago, characters: Array(cast))
    scene.update_columns(story_timestamp: nil) if at.nil?
    scene
  end

  # NOT named `run`: that is `Minitest::Runnable#run`, and overriding it makes
  # the runner call this before setup has assigned anything.
  def backfill(dry_run: false) = Character::WhereaboutsBackfill.new(@story).run(dry_run: dry_run)

  test "somebody recorded in one room is placed there" do
    rowe = create(:character, story: @story, fullname: "Halkett Rowe")
    scene_in(@office, at: 1.hour.ago, cast: rowe)

    answer = backfill.sole

    assert_predicate answer, :placed?
    assert_equal @office, rowe.reload.location
    assert_equal @office, answer.location
  end

  # The LATEST moment decides, on story time rather than on id -- a scene
  # backdated into the story's past does not win, which is the same rule
  # `Scene::Generator` followed when it read holdovers.
  test "the latest arrival that recorded them decides" do
    rowe = create(:character, story: @story, fullname: "Halkett Rowe")
    scene_in(@office, at: 2.hours.ago, cast: rowe)
    scene_in(@closet, at: 1.hour.ago, cast: rowe)

    backfill

    assert_equal @closet, rowe.reload.location
  end

  test "two rooms at the same moment leave them nowhere, and say which two" do
    rowe = create(:character, story: @story, fullname: "Halkett Rowe")
    at = 1.hour.ago
    scene_in(@office, at: at, cast: rowe)
    scene_in(@closet, at: at, cast: rowe)

    answer = backfill.sole

    assert_predicate answer, :ambiguous?
    assert_predicate rowe.reload, :nowhere?
    assert_equal [ "The Supply Closet", "Ward Office 12" ], answer.rooms
  end

  # A scene with no story time is invisible to the story's own clock, so it
  # cannot be ordered against one that has it. Two rooms with no order between
  # them is the same refusal.
  test "scenes with no story time and no agreement leave them nowhere" do
    rowe = create(:character, story: @story, fullname: "Halkett Rowe")
    scene_in(@office, at: nil, cast: rowe)
    scene_in(@closet, at: nil, cast: rowe)

    assert_predicate backfill.sole, :ambiguous?
    assert_predicate rowe.reload, :nowhere?
  end

  test "an untimed scene disagreeing with a timed one is still a refusal" do
    rowe = create(:character, story: @story, fullname: "Halkett Rowe")
    scene_in(@office, at: 1.hour.ago, cast: rowe)
    scene_in(@closet, at: nil, cast: rowe)

    assert_predicate backfill.sole, :ambiguous?
    assert_predicate rowe.reload, :nowhere?
  end

  test "untimed scenes that all agree still decide" do
    rowe = create(:character, story: @story, fullname: "Halkett Rowe")
    scene_in(@office, at: nil, cast: rowe)
    scene_in(@office, at: nil, cast: rowe)

    assert_predicate backfill.sole, :placed?
    assert_equal @office, rowe.reload.location
  end

  test "somebody no scene ever recorded is left nowhere" do
    rowe = create(:character, story: @story, fullname: "Halkett Rowe")

    assert_equal :unrecoverable, backfill.sole.outcome
    assert_predicate rowe.reload, :nowhere?
  end

  # THE PARTY IS NOT THIS COLUMN'S. The protagonist and any companion are
  # wherever the playthrough is, and every old arrival cast names the
  # protagonist -- so backfilling from one would write a single player's
  # position onto the story.
  test "the protagonist and companions are skipped entirely" do
    hero = create(:character, :protagonist, story: @story)
    friend = create(:character, :companion, story: @story)
    scene_in(@office, at: 1.hour.ago, cast: [ hero, friend ])

    assert_equal [], backfill
    assert_predicate hero.reload, :nowhere?
    assert_predicate friend.reload, :nowhere?
  end

  # This is a backfill, not a re-derivation: the records win over the history
  # everywhere else in this app and they win here too.
  test "somebody who already has a whereabouts is not touched" do
    rowe = create(:character, story: @story, fullname: "Halkett Rowe", location: @closet)
    scene_in(@office, at: 1.hour.ago, cast: rowe)

    assert_equal [], backfill
    assert_equal @closet, rowe.reload.location
  end

  test "a dry run answers without writing" do
    rowe = create(:character, story: @story, fullname: "Halkett Rowe")
    scene_in(@office, at: 1.hour.ago, cast: rowe)

    assert_predicate backfill(dry_run: true).sole, :placed?
    assert_predicate rowe.reload, :nowhere?
  end
end
