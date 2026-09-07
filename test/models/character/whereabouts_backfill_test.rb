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

  # NOWHERE ON PURPOSE IS NOT A GAP: an old arrival cast that names somebody a
  # world has removed from itself is exactly the evidence that must not win.
  # `Character::Registry` refuses to place them for the same reason.
  test "somebody absent on purpose is skipped entirely" do
    perrin = create(:character, :absent, story: @story, fullname: "Perrin Lasco")
    scene_in(@office, at: 1.hour.ago, cast: perrin)

    assert_equal [], backfill
    assert_predicate perrin.reload, :absent?
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

  # --- and where in the room they are standing, since slice 4 ---------------

  # A RECOVERY PUTS SOMEBODY IN A ROOM, SO IT PUTS THEM SOMEWHERE IN IT: the
  # write goes through `Character#move_to!`, which is the one statement that
  # owns a whereabouts and a position together. A backfill that wrote
  # `location:` alone would leave somebody standing nowhere in particular in a
  # laid-out room, and nothing afterwards would ever place them -- unplaced is a
  # legal state, so no doctor finding and no invariant would say so.
  test "somebody recovered into a laid-out room stands somewhere inside its box" do
    place = create(:location, :stub, :with_a_footprint, story: @story, name: "The Custom House")
    long = create(:location, story: @story, parent_location: place, name: "The Long Room",
                             x: 0, y: 0, z: 0, width: 7, depth: 4)
    rowe = create(:character, story: @story, fullname: "Halkett Rowe")
    scene_in(long, at: 1.hour.ago, cast: rowe)

    backfill

    assert_equal long, rowe.reload.location
    assert_equal Location::Spot.new(**Location::Placement.in_the_world(long, rowe)), rowe.position
    assert long.box.contains?(rowe.position), "#{rowe.position} is outside #{long.box}"
  end

  # THE ORDINARY CASE, and every room a backfill can reach in any world in the
  # repository today: a room with no box opens no plane, so there is no cell to
  # pick and a flat world is recovered exactly as it was before this slice.
  test "somebody recovered into a room with no box is left unplaced" do
    rowe = create(:character, story: @story, fullname: "Halkett Rowe")
    scene_in(@office, at: 1.hour.ago, cast: rowe)

    backfill

    assert_equal @office, rowe.reload.location
    assert_nil rowe.position
  end

  test "a dry run writes no position either" do
    place = create(:location, :stub, :with_a_footprint, story: @story, name: "The Custom House")
    long = create(:location, story: @story, parent_location: place, name: "The Long Room",
                             x: 0, y: 0, z: 0, width: 7, depth: 4)
    rowe = create(:character, story: @story, fullname: "Halkett Rowe")
    scene_in(long, at: 1.hour.ago, cast: rowe)

    assert_predicate backfill(dry_run: true).sole, :placed?
    assert_predicate rowe.reload, :nowhere?
    assert_nil rowe.position
  end
end
