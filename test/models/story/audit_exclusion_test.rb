require "test_helper"

# THE TURNS THE ENGINE WROTE ITSELF, AND WHY THE AUDIT DOES NOT READ THEM AS
# NARRATION.
#
# `Scene#engine_authored?` is true of a row whose `resolved_action` is one the
# classifier's closed enum does not contain -- today, the one `Scene` that
# closes a fight (`Playthrough::Fight`), whose description is the engine's own
# sentence about its own dice. Every check in `Story::Audit` reads `description`
# as narration, so auditing that row would count the app's own words against the
# app.
#
# THE EXCLUSION IS A SMALLER DENOMINATOR AND NEVER A LOWER RATE, and
# `rake game:score` prints the count so it cannot hide -- which is the whole of
# what makes it honest rather than convenient.
class Story::AuditExclusionTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @room = create(:location, story: @story, name: "Ward Office 12")
    @first = create(:scene, story: @story, location: @room, resolved_action: "examine",
                            description: "You look at the daybook.", typed: "look at the daybook")
    @second = create(:scene, story: @story, location: @room, previous_scene: @first,
                             resolved_action: "take", description: "You pick it up.", typed: "take it")
  end

  def audit = Story::Audit.new(@story)

  test "an ordinary story excludes nothing" do
    assert_equal [ @first, @second ], audit.scenes
    assert_equal 0, audit.excluded
  end

  test "a fight's closing scene is out of the sweep and counted as excluded" do
    fight = create(:scene, story: @story, location: @room, previous_scene: @second,
                           resolved_action: "attack",
                           description: "The fight in Ward Office 12 is over after 2 rounds.")

    assert_predicate fight, :engine_authored?
    assert_not_includes audit.scenes, fight
    assert_equal 1, audit.excluded
  end

  # THE DENOMINATOR FOLLOWS, which is what keeps a rate honest: the check did
  # not become cleaner, it had one fewer passage to judge.
  test "every check's denominator shrinks with it rather than its rate falling" do
    before = audit.judgeable_for(:truncated_prose)
    create(:scene, story: @story, location: @room, previous_scene: @second, resolved_action: "attack",
                   description: "The fight in Ward Office 12 is over after 2 rounds.")

    assert_equal before, Story::Audit.new(@story).judgeable_for(:truncated_prose)
  end

  # `Eval::Richness` READS `Story::Audit#scenes` (through `Eval::RunSet`), so it
  # is excluded by the same one statement rather than by a second copy of the
  # rule.
  test "richness reads the audit's own list, so engine copy scores no commitments" do
    create(:scene, story: @story, location: @room, previous_scene: @second, resolved_action: "attack",
                   description: "The fight in Ward Office 12 is over after 2 rounds. " \
                                "Ward Office 12. Ward Office 12.")

    assert_equal 2, audit.scenes.size
  end

  # THE BOARD PRINTS IT, and a frozen corpus -- which carries no fights -- says
  # zero rather than not answering.
  test "the scoreboard sums the exclusions and the frozen corpora report none" do
    create(:scene, story: @story, location: @room, previous_scene: @second, resolved_action: "attack",
                   description: "The fight in Ward Office 12 is over after 2 rounds.")

    assert_equal 1, Story::Scoreboard.database(Story.where(id: @story.id)).excluded
    assert_equal 0, Story::Scoreboard.corpus.excluded
    assert_equal 0, Story::Scoreboard.transitions.excluded
  end
end
