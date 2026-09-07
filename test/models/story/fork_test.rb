require "test_helper"

# THE GUARANTEE THE WHOLE FEATURE EXISTS FOR: forking a story leaves the story
# it was forked from exactly as it was. `Playthrough::Feedback` REFERENCES the
# `Scene` it judged, so a reset that deleted scenes would delete the evidence
# the scoreboard's agreement figures are computed from -- which is why the
# captain chose a fork over a rewind, and why the counts below are asserted
# rather than reasoned about.
class Story::ForkTest < ActiveSupport::TestCase
  include ForkableWorld

  test "the original's playthroughs, scenes and verdicts are untouched" do
    story = seeded_world
    play!(story)

    before = original_counts(story)
    forked = Story::Fork.new(story).create!

    assert_equal before, original_counts(story.reload)
    assert_not_equal story.id, forked.id
  end

  test "the fork has nobody's progress in it" do
    story = seeded_world
    play!(story)

    forked = Story::Fork.new(story).create!

    assert_equal 0, forked.playthroughs.count
    assert_equal 0, forked.scenes.where(is_opening: false).count
    assert_equal 0, Playthrough::Feedback.where(playthrough: forked.playthroughs).count
    # The one Scene that is world comes with it, which is what makes a fork
    # playable from its first screen with no model call.
    assert forked.opening_scene.present?
  end

  test "the fork carries the generation-time world and not what play realized" do
    story = seeded_world
    play!(story)

    forked = Story::Fork.new(story).create!

    assert_equal [ "The Office", "The Hallway" ], forked.locations.order(:id).pluck(:name)
    assert_equal "The Office", forked.opening_location.name
    assert forked.locations.find_by(name: "The Hallway").stub?
    assert_equal [ "Corbel Ashe", "Vesper Aal" ], forked.characters.order(:fullname).pluck(:fullname)
    assert_nil Item.in_story(forked).templates.find_by(name: "a thing play made")
  end

  test "the fork is doctor-healthy and cost no model call" do
    story = seeded_world
    play!(story)

    forked = BaseAgent.stub(:new, ->(*) { flunk "forking a story asked a model something" }) do
      Story::Fork.new(story).create!
    end

    doctor = Story::Doctor.new(forked)
    assert doctor.healthy?, "the fork is not healthy: #{doctor.findings.map(&:message).join("; ")}"
  end

  # The loader keys a story on its TITLE, so a fork under the original's name
  # would REWRITE the original rather than making a second story. This is the
  # test that pins it.
  test "a fork is titled so the loader cannot land on the story it came from" do
    story = seeded_world

    assert_equal "A Forkable World (fork 1)", Story::Fork.new(story).title
    Story::Fork.new(story).create!
    assert_equal "A Forkable World (fork 2)", Story::Fork.new(story).title
  end

  test "forking twice makes two stories rather than overwriting one" do
    story = seeded_world

    first = Story::Fork.new(story).create!
    second = Story::Fork.new(story).create!

    assert_not_equal first.id, second.id
    assert_equal 3, Story.count
  end

  test "a requested title that is taken is refused rather than loaded over" do
    story = seeded_world
    create(:story, title: "Taken")

    error = assert_raises(Story::Fork::Refused) { Story::Fork.new(story, title: "Taken").create! }
    assert_match "already exists", error.message
  end

  test "a requested title is used as written" do
    story = seeded_world

    forked = Story::Fork.new(story, title: "A Second Run").create!

    assert_equal "A Second Run", forked.title
  end

  # A shared universe would put the fork's people on the ORIGINAL's race rows,
  # where a re-seed of either story could change `monstrous` under the other --
  # and `Story::Deletion` keeps a universe alive for as long as any story uses
  # it, so deleting either would leave the other's world half there.
  test "the fork gets a universe of its own" do
    story = seeded_world

    forked = Story::Fork.new(story).create!

    assert_not_equal story.universe_id, forked.universe_id
    assert_equal story.universe.races.order(:name).pluck(:name), forked.universe.races.order(:name).pluck(:name)
    assert_equal forked.universe_id, forked.characters.first.race.universe_id
  end

  test "a fork can be forked, because it is snapshotted as it is written" do
    story = seeded_world
    forked = Story::Fork.new(story).create!

    assert Story::Snapshot.for(forked).present?
    assert_equal "A Forkable World (fork 1) (fork 1)", Story::Fork.new(forked).title
  end

  test "a stored snapshot is preferred to a derivation" do
    story = seeded_world
    Story::Snapshot.capture!(story)
    play!(story)

    fork = Story::Fork.new(story)

    assert fork.snapshot?
    assert_nil fork.derivation
    assert_equal [], fork.refusals
    assert_equal [ "The Office", "The Hallway" ], fork.create!.locations.order(:id).pluck(:name)
  end

  def original_counts(story)
    {
      playthroughs: story.playthroughs.count,
      scenes: story.scenes.count,
      verdicts: Playthrough::Feedback.where(playthrough: story.playthroughs).count,
      locations: story.locations.count,
      characters: story.characters.count,
      items: Item.in_story(story).count
    }
  end
end
