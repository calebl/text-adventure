require "test_helper"

# THE ONE BLOCK THE GENERATOR IS TOLD ABOUT THE ARC, and the record-only checks
# that judge it -- because `rake eval:realization` provably cannot, today.
#
# WHY THE BENCH CANNOT JUDGE IT. Its corpus stages five worlds -- The Iron Gate
# Descends (the frozen fixture copy), The Lunar Cartographer, The Quay House,
# The Salt Assizes and The Unrecorded Hour -- and NOT ONE of them carries a
# `quests:` block. So `#arc_block` is empty for all twenty-two cases and the
# prompt is byte-for-byte what it was: measured, not assumed --
# `rake eval:realization_digest` reads the same `08d08a01235d89d3` before and
# after this change, which is why `room-people-after` is still a baseline for
# this tree. `#the_bench_worlds_send_an_unchanged_prompt` below is that fact as
# a test, and it FAILS the day one of them gains an arc -- which is the day a
# round can be bought and has to be.
#
# SO WHAT IS ASSERTED HERE IS EVERY BRANCH OF THE BLOCK, on records: that it
# names the right kind of thing in the vocabulary of the seam that can supply
# it, that it is silent for every world that has no arc, that it never carries
# the conclusion, and that it does not follow one player around.
class Location::GeneratorArcTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @room = create(:location, :stub, story: @story, name: "obsidian maw")
  end

  def context(room = @room) = Location::Generator.new(room).send(:story_context)

  # --- a world with no arc sends the prompt it always sent --------------------

  test "a world with no arc says nothing about one" do
    assert_not_includes context, "Where This Story Is Going"
  end

  # THE MEASUREMENT THAT REPLACED A BENCH ROUND. Every world the realization
  # corpus stages, asked whether it has an arc. While none does, the block
  # cannot render in the bench and the stored baseline stays a before side; the
  # day one does, this fails and says what to do about it.
  test "the bench worlds send an unchanged prompt" do
    staged = YAML.safe_load_file(Eval::Realization::CORPUS, permitted_classes: [ Date, Time ])
                 .fetch("cases").map { |kase| kase.fetch("story") }.uniq

    staged.each do |title|
      document = YAML.safe_load_file(Eval::Realization.world_file(title), permitted_classes: [ Date, Time ])

      assert_nil document["quests"],
                 "#{title} has an arc now, so `rake eval:realization` CAN see the story block -- " \
                 "buy an after side at today's digest and judge it against room-people-after"
    end
  end

  # AND THE EMPTY BLOCK ADDS NO WHITESPACE EITHER, which is not a nicety: an
  # empty interpolation on a line of its own moved the bench's prompt digest for
  # all nine shapes, and would have cost a paid round to measure one newline.
  test "an absent arc leaves the prompt byte-for-byte as it was" do
    before = context

    quest = create(:quest, story: @story, title: "The Long Way Down")
    create(:quest_outcome, :default, quest: quest, name: "rescued")
    quest.steps.create!(position: 1, summary: "Go down.", trigger_kind: "reach_location",
                        target_name: "Blackfang Warren")
    quest.destroy

    assert_equal before, context(@room.reload)
  end

  # --- what it says, per kind -------------------------------------------------

  test "a place is asked for in the vocabulary of the call that names a way out" do
    arc_wanting(:reach_location, "Blackfang Warren", teaser: "They hold him below the old workings.")

    assert_includes context, "## Where This Story Is Going"
    assert_includes context, "next: Find where they are keeping him."
    assert_includes context, %(needs a PLACE called "Blackfang Warren", somewhere a player can walk to)
    assert_includes context, "There is no such place in this world yet."
    assert_includes context, "They hold him below the old workings."
  end

  test "a person is asked for in the vocabulary of the call that writes a room's cast" do
    arc_wanting(:speak_to, "Prince Aurel Durn")

    assert_includes context, %(needs a PERSON called "Prince Aurel Durn", standing somewhere a player can reach)
    assert_includes context, "There is nobody of that name in this world yet."
  end

  test "a thing is asked for in the vocabulary of the call that furnishes a floor" do
    arc_wanting(:hold_item, "the cell key")

    assert_includes context, %(needs a THING called "the cell key", lying somewhere a player can pick it up)
    assert_includes context, "There is no such thing in this world yet."
  end

  test "the engine's own trigger words never reach the prompt" do
    arc_wanting(:reach_location, "Blackfang Warren")

    assert_not_includes context, "reach_location"
    assert_not_includes context, "trigger"
  end

  # --- what it will not say ---------------------------------------------------

  test "the conclusion is never in it, and neither is the rest of the arc" do
    quest = arc_wanting(:reach_location, "Blackfang Warren")
    quest.steps.create!(position: 2, summary: "And get him out again.", trigger_kind: "speak_to",
                        target_name: "Prince Aurel Durn")

    assert_not_includes context, "carried back through the iron gate alive"
    assert_not_includes context, "And get him out again.", "three beats would be an outline"
    assert_not_includes context, "The Long Way Down"
  end

  test "a step the world has already grown is not asked for again" do
    quest = arc_wanting(:reach_location, "Blackfang Warren")
    warren = create(:location, story: @story, name: "Blackfang Warren")
    quest.steps.first.bind!(warren, at: @story.start_time)

    assert_not_includes context(@room.reload), "Where This Story Is Going"
  end

  test "a doomed arc asks for nothing, because its beats are unreachable by design" do
    arc_wanting(:reach_location, "Blackfang Warren").update!(status: "doomed")

    assert_not_includes context, "Where This Story Is Going"
  end

  test "a time_passed beat asks the world for nothing, because the clock already exists" do
    quest = create(:quest, story: @story, title: "The Long Way Down")
    create(:quest_outcome, :default, quest: quest, name: "rescued")
    create(:quest_step, quest: quest, position: 1, minutes: 40, summary: "Wait it out.")

    assert_not_includes context, "Where This Story Is Going"
  end

  # --- and it is the WORLD's next beat, not one player's ----------------------
  #
  # Realization is the world growing, and two people playing one world must not
  # be walked into two different rooms. So the generator reads the arc's first
  # UNBOUND step and the narrator reads the player's first UNREACHED one, and
  # this is the one place in the app the two deliberately differ.

  test "it does not follow one player's progress" do
    quest = arc_wanting(:reach_location, "Blackfang Warren")
    game = create(:playthrough, story: @story, current_location: @room)
    Playthrough::Beat.reach!(game, quest.steps.first, at: @story.start_time)

    assert_includes context(@room.reload), %(needs a PLACE called "Blackfang Warren"),
                    "the beat is reached in one game and the WORLD still has no such place"
  end

  private

  def arc_wanting(kind, name, teaser: nil)
    quest = create(:quest, story: @story, title: "The Long Way Down", origin: "generated")
    create(:quest_outcome, :default, quest: quest, name: "rescued",
                                     summary: "The prince is carried back through the iron gate alive.")
    create(:quest_step, kind, quest: quest, position: 1, summary: "Find where they are keeping him.",
                              target_name: name, teaser: teaser)
    quest
  end
end
