require "test_helper"

# THE STEPS, AGAINST REAL ROWS. `Update::RunnerTest` covers the machinery with
# fakes; this covers the three things a step's own code decides, on data:
#
#   it reports the work it did;
#   `dry_run: true` writes NOTHING, which is the promise `bin/update --dry-run`
#     makes to the captain and the one it can only keep step by step;
#   a second call has nothing to do, which is what makes the whole command
#     runnable after every pull rather than only after the suspicious ones.
#
# The backfills' own reasoning is tested where they live
# (`Character::WhereaboutsBackfillTest` and its neighbours); these tests are
# about the registry entry, not about the recovery rule.
class Update::StepsTest < ActiveSupport::TestCase
  # A world with somebody in it who has no whereabouts, and one arrival scene
  # that recorded them in a room -- the shape a database older than PR 109 is
  # in, reduced to the two rows the step reads.
  def a_world_with_a_misplaced_person
    story = create(:story)
    create(:character, :protagonist, story: story)
    room = create(:location, story: story, name: "Ward Office 12")
    somebody = create(:character, story: story, fullname: "Halkett Rowe")
    create(:scene, story: story, location: room, story_timestamp: story.start_time, characters: [ somebody ])

    [ story, somebody, room ]
  end

  test "the whereabouts step places somebody and says where" do
    _story, somebody, room = a_world_with_a_misplaced_person

    report = Update::Steps::BackfillWhereabouts.new.call

    assert_predicate report, :changed?
    assert_equal [ "#{_story.title}: Halkett Rowe -> Ward Office 12" ], report.lines
    assert_equal room, somebody.reload.location
  end

  test "the whereabouts step writes nothing in a dry run, and still says what it would do" do
    _story, somebody, _room = a_world_with_a_misplaced_person

    report = Update::Steps::BackfillWhereabouts.new(dry_run: true).call

    assert_predicate report, :changed?
    assert_nil somebody.reload.location, "a dry run placed somebody"
  end

  test "the whereabouts step has nothing to do the second time" do
    a_world_with_a_misplaced_person

    Update::Steps::BackfillWhereabouts.new.call
    again = Update::Steps::BackfillWhereabouts.new.call

    assert_predicate again, :nothing_to_do?
    assert_empty again.lines
  end

  # AMBIGUOUS IS NOT PENDING WORK. Two rooms recorded her at one moment, so the
  # backfill refuses for ever -- and a step that reported that as something
  # still to do would cry wolf on every pull the captain ever makes.
  test "a refusal the backfill will never resolve is a note, not a change" do
    story = create(:story)
    create(:character, :protagonist, story: story)
    somebody = create(:character, story: story, fullname: "Halkett Rowe")
    at = story.start_time
    [ "Ward Office 12", "The Causeway Court" ].each do |name|
      room = create(:location, story: story, name: name)
      create(:scene, story: story, location: room, story_timestamp: at, characters: [ somebody ])
    end

    report = Update::Steps::BackfillWhereabouts.new.call

    assert_predicate report, :nothing_to_do?
    assert_nil somebody.reload.location
    assert_equal 1, report.notes.size
    assert_match(/Halkett Rowe is left nowhere/, report.notes.first)
  end

  test "the transitions step labels a turn from the classifier's stored answer" do
    story = create(:story)
    create(:character, :protagonist, story: story)
    room = create(:location, story: story, name: "Ward Office 12")
    scene = create(:scene, story: story, location: room, typed: "go to ward office 12")
    stored_classifier_answer(scene, intent: "move", target: "Ward Office 12")

    report = Update::Steps::BackfillTransitions.new.call

    assert_predicate report, :changed?
    assert_match(/1 turn\(s\) labelled/, report.lines.first)
    assert_equal "move", scene.reload.resolved_action
    assert_equal room, scene.acted_on
    assert_predicate Update::Steps::BackfillTransitions.new.call, :nothing_to_do?
  end

  test "the transitions step writes nothing in a dry run" do
    story = create(:story)
    create(:character, :protagonist, story: story)
    room = create(:location, story: story, name: "Ward Office 12")
    scene = create(:scene, story: story, location: room)
    stored_classifier_answer(scene, intent: "move", target: "Ward Office 12")

    assert_predicate Update::Steps::BackfillTransitions.new(dry_run: true).call, :changed?
    assert_nil scene.reload.resolved_action, "a dry run labelled a turn"
  end

  # A TURN NOTHING CAN SPEAK FOR is reported as a note on every run, for ever,
  # and never counted as work: there is no stored answer to read.
  test "an unrecoverable turn is a note, not a change" do
    story = create(:story)
    create(:character, :protagonist, story: story)
    create(:scene, story: story, location: create(:location, story: story))

    report = Update::Steps::BackfillTransitions.new.call

    assert_predicate report, :nothing_to_do?
    assert_match(/1 turn\(s\) left blank/, report.notes.first)
  end

  test "the item step has nothing to do when the world holds nothing" do
    story = create(:story)
    create(:character, :protagonist, story: story)

    assert_predicate Update::Steps::BackfillItems.new.call, :nothing_to_do?
  end

  # THE ONE STEP WHERE "NOTHING TO DO" TOOK READING RATHER THAN ASSUMING. The
  # row phase re-derives the same answers on every run for ever, because the
  # world's own rows stay where they are; what makes the second run quiet is
  # that every playthrough already holds the copies it is owed.
  test "the item step gives a game its copies once and then has nothing to do" do
    story = create(:story)
    protagonist = create(:character, :protagonist, story: story)
    room = create(:location, story: story)
    create(:item, character: protagonist, location: nil, name: "Assize tide-slate")
    create(:item, :lying, location: room, name: "a hand bell")
    playthrough = create(:playthrough, story: story, character: protagonist, current_location: room)
    playthrough.items.destroy_all

    report = Update::Steps::BackfillItems.new.call

    assert_predicate report, :changed?
    assert_match(/takes its own copy of 2 thing\(s\)/, report.lines.first)
    assert_equal [ "Assize tide-slate" ], playthrough.reload.carried.pluck(:name)
    assert_equal [ "a hand bell" ], playthrough.items_lying_in(room).pluck(:name)
    assert_predicate Update::Steps::BackfillItems.new.call, :nothing_to_do?
  end

  test "the item step writes nothing in a dry run" do
    story = create(:story)
    protagonist = create(:character, :protagonist, story: story)
    room = create(:location, story: story)
    create(:item, character: protagonist, location: nil, name: "Assize tide-slate")
    playthrough = create(:playthrough, story: story, character: protagonist, current_location: room)
    playthrough.items.destroy_all

    assert_predicate Update::Steps::BackfillItems.new(dry_run: true).call, :changed?
    assert_empty playthrough.reload.carried, "a dry run handed out the starting kit"
  end

  # `missing_start_time` is a `safe` finding: the answer is the story's own
  # earliest scene, already on file. Nothing here is allowed to ask a model.
  test "the repair step fixes a safe finding and never asks for a model" do
    story = create(:story)
    create(:character, :protagonist, story: story)
    scene = create(:scene, story: story, location: create(:location, story: story), story_timestamp: 3.days.ago)
    story.update_columns(start_time: nil)

    assert_not Update::Steps::SafeRepairs.model_calls?
    report = Update::Steps::SafeRepairs.new.call

    assert_predicate report, :changed?
    assert_match(/ok set start_time/, report.lines.join("\n"))
    assert_in_delta scene.story_timestamp, story.reload.start_time, 1.second
    assert_predicate Update::Steps::SafeRepairs.new.call, :nothing_to_do?
  end

  test "the repair step writes nothing in a dry run, and says what it would fix" do
    story = create(:story)
    create(:character, :protagonist, story: story)
    create(:scene, story: story, location: create(:location, story: story), story_timestamp: 3.days.ago)
    story.update_columns(start_time: nil)

    report = Update::Steps::SafeRepairs.new(dry_run: true).call

    assert_predicate report, :changed?
    assert_match(/would fix/, report.lines.first)
    assert_nil story.reload.start_time, "a dry run repaired a story"
  end

  test "the repair step reports what needs a hand as a note and does not act on it" do
    story = create(:story)
    create(:character, :protagonist, story: story)

    report = Update::Steps::SafeRepairs.new.call

    assert_predicate report, :nothing_to_do?
    assert_predicate report.notes, :any?, "a story with no locations at all has findings nothing can derive"
    assert_match(/by hand/, report.notes.first)
  end

  # --- the stat block backfill ---------------------------------------------

  test "the stat block step rolls a body for somebody who has none" do
    story = create(:story)
    nobody = create(:character, :without_a_stat_block, story: story)

    report = Update::Steps::BackfillStatBlocks.new.call

    assert_predicate report, :changed?
    assert_match(/rolled 1 stat block/, report.lines.first)
    assert_predicate nobody.reload, :stat_block?
  end

  test "the stat block step writes nothing in a dry run, and still says what it would do" do
    story = create(:story)
    nobody = create(:character, :without_a_stat_block, story: story)

    report = Update::Steps::BackfillStatBlocks.new(dry_run: true).call

    assert_predicate report, :changed?
    assert_not_predicate nobody.reload, :stat_block?
  end

  test "the stat block step has nothing to do the second time" do
    create(:character, :without_a_stat_block, story: create(:story))
    Update::Steps::BackfillStatBlocks.new.call

    assert_predicate Update::Steps::BackfillStatBlocks.new.call, :nothing_to_do?
  end

  # A roll cannot be ambiguous, so unlike every other backfill in the registry
  # this one has no permanent refusals to report.
  test "the stat block step has no notes at all" do
    create(:character, :without_a_stat_block, story: create(:story))

    assert_empty Update::Steps::BackfillStatBlocks.new.call.notes
  end

  test "the doctor step reports every story and writes nothing" do
    story = create(:story)
    create(:character, :protagonist, story: story)

    report = Update::Steps::Doctor.new.call

    assert_predicate report, :nothing_to_do?, "the doctor counted as a change"
    assert_match(/##{story.id} #{Regexp.escape(story.title)}/, report.lines.first)
    assert_match(/1 story:/, report.lines.last)
  end

  test "the doctor step says so when there are no stories at all" do
    assert_equal [ "no stories in this database yet" ], Update::Steps::Doctor.new.call.lines
  end

  private

  # The classifier's own structured reply, filed against the scene it produced,
  # exactly as `BaseAgent#attribute_to!` files it -- `content_raw` on an
  # assistant message in a chat whose purpose is "classifier". It is the only
  # thing `Scene::TransitionBackfill` reads.
  def stored_classifier_answer(scene, intent:, target:)
    chat = create(:chat, purpose: "classifier")
    create(:message, chat: chat, role: "assistant", scene: scene, content: "",
                     content_raw: { "intent" => intent, "target" => target }.to_json)
  end
end
