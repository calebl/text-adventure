require "test_helper"

# The sweep, check by check. Every test here is either "this flag fires and the
# records prove it" or "this does NOT fire, and here is the real prose that
# would have fooled a vocabulary scanner".
#
# Offline by construction: nothing in this file stubs an agent, because nothing
# in `Story::Audit` can reach one.
class Story::AuditTest < ActiveSupport::TestCase
  def setup
    @story = create(:story, start_time: Time.utc(2026, 3, 1, 21, 0))
    @protagonist = create(:character, story: @story, fullname: "Isbet Marrow", nickname: "Iz",
                                      is_protagonist: true)
    @here = create(:location, story: @story, name: "Room 3")
    @there = create(:location, story: @story, name: "The Long Corridor")
  end

  def audit = Story::Audit.new(@story.reload)

  def connect(from, to)
    create(:location_connection, location: from, connected_location: to,
                                 distance: "adjacent", travel_method: "walking")
    create(:location_connection, location: to, connected_location: from,
                                 distance: "adjacent", travel_method: "walking")
  end

  def scene_at(location, description:, previous: nil, minutes: 5, **attributes)
    create(:scene, story: @story, location: location, previous_scene: previous,
                   description: description,
                   story_timestamp: (previous&.story_timestamp || @story.start_time) + minutes.minutes,
                   **attributes)
  end

  # --- no model, no network -------------------------------------------------

  test "a clean story reports nothing and says how much it read" do
    connect(@here, @there)
    first = scene_at(@here, description: "The lamp gutters.")
    scene_at(@there, description: "The corridor keeps going.", previous: first)

    result = audit

    assert_predicate result, :clean?
    assert_equal 2, result.scanned
    assert_empty result.flags
    assert_equal "2 scenes, nothing to report", result.headline
  end

  test "the audit reads records and never a model" do
    scene_at(@here, description: "The lamp gutters.")

    # BaseAgent.new raises if anything tries to reach a model at all.
    BaseAgent.stub(:new, ->(*) { raise "the sweep must not call a model" }) do
      assert_empty audit.flags
    end
  end

  # --- the player ended up somewhere the graph forbids ----------------------

  test "two consecutive scenes with no edge between them is a contradiction" do
    first = scene_at(@here, description: "The lamp gutters.")
    scene_at(@there, description: "You are somehow in the corridor.", previous: first)

    flags = audit.contradictions

    assert_equal 1, flags.size
    assert_equal :unreachable_transition, flags.first.code
    assert_match(/no edge between them/, flags.first.headline)
    assert_equal "Room 3", flags.first.evidence[:from]
    assert_equal "The Long Corridor", flags.first.evidence[:to]
  end

  test "a real edge is no contradiction" do
    connect(@here, @there)
    first = scene_at(@here, description: "The lamp gutters.")
    scene_at(@there, description: "The corridor keeps going.", previous: first)

    assert_empty audit.flags
  end

  test "staying in the same room is not a transition at all" do
    first = scene_at(@here, description: "The lamp gutters.")
    scene_at(@here, description: "You look at the map again.", previous: first)

    assert_empty audit.flags
  end

  # A one-way edge is a different defect, and Story::Doctor is where it belongs
  # -- but the sweep says which it found, so the flag can be judged.
  test "a one-way edge is reported as one rather than as a missing edge" do
    create(:location_connection, location: @there, connected_location: @here,
                                 distance: "adjacent", travel_method: "walking")
    first = scene_at(@here, description: "The lamp gutters.")
    scene_at(@there, description: "The corridor keeps going.", previous: first)

    assert_match(/one-way/, audit.contradictions.first.evidence["edge back"])
  end

  # THE GUARD THAT KEEPS THIS HONEST. A mobile location's edges are repointed by
  # WorldMechanic on the story's clock, so the graph read now is not the graph
  # the player walked. Calling that a violation would be reporting the world
  # working as designed.
  test "a transition is not judged when the world moved one of its ends afterwards" do
    mechanic = create(:world_mechanic, story: @story, kind: "shuffle_connections", cadence: "nightly")
    first = scene_at(@here, description: "The lamp gutters.")
    second = scene_at(@there, description: "The corridor keeps going.", previous: first)
    create(:world_event, story: @story, world_mechanic: mechanic,
                         occurred_at: second.story_timestamp, summary: "The lanes rearranged.",
                         locations: [ @there ])

    result = audit

    assert_empty result.flags
    assert_equal 1, result.unjudged.size
    assert_equal :unreachable_transition, result.unjudged.first.code
    assert_match(/the world moved/, result.unjudged.first.reason)
  end

  test "a world event somewhere else does not excuse a missing edge" do
    mechanic = create(:world_mechanic, story: @story, kind: "shuffle_connections", cadence: "nightly")
    elsewhere = create(:location, story: @story, name: "The Bell of Saint Aravel")
    first = scene_at(@here, description: "The lamp gutters.")
    second = scene_at(@there, description: "You are somehow in the corridor.", previous: first)
    create(:world_event, story: @story, world_mechanic: mechanic,
                         occurred_at: second.story_timestamp, summary: "The lanes rearranged.",
                         locations: [ elsewhere ])

    assert_equal 1, audit.contradictions.size
  end

  test "a scene with no story time is not judged against the world's events" do
    first = scene_at(@here, description: "The lamp gutters.")
    second = build(:scene, story: @story, location: @there, previous_scene: first,
                           description: "You are somehow in the corridor.", story_timestamp: nil)
    second.save!(validate: false)

    result = audit

    assert_empty result.flags
    assert_equal 1, result.unjudged.size
    assert_match(/no story time/, result.unjudged.first.reason)
  end

  # --- the player is told they have something they do not -------------------

  test "the player told they are carrying something the records give to somebody else" do
    landlord = create(:character, story: @story, fullname: "Grenn Ollivar")
    create(:item, character: landlord, name: "revolver")
    scene_at(@here, description: "You reach into your coat and draw your revolver, its weight familiar.")

    flags = audit.contradictions

    assert_equal 1, flags.size
    assert_equal :item_not_held, flags.first.code
    assert_match(/held by Grenn Ollivar/, flags.first.headline)
    assert_match(/draw your revolver/, flags.first.evidence[:claim])
  end

  test "the player told they picked up something the records still have on the floor" do
    create(:item, :lying, location: @here, name: "Brass Key")
    scene_at(@here, description: "You take the brass key from the table and pocket it.")

    assert_equal :item_not_held, audit.contradictions.first.code
  end

  test "an item the player really holds is never flagged" do
    create(:item, character: @protagonist, name: "lunar compass")
    scene_at(@here, description: "You read your lunar compass and the needle wanders.")

    assert_empty audit.flags
  end

  # --- the mentions a vocabulary scanner would have flagged -----------------

  # Every string in this section is real narration from
  # test/fixtures/files/narration_corpus.json. The old spike flagged all of
  # them; the claim-shaped patterns flag none.

  test "a mention that is not a claim is not a contradiction" do
    landlord = create(:character, story: @story, fullname: "Grenn Ollivar")
    create(:item, character: landlord, name: "revolver")
    create(:item, character: landlord, name: "daybook")

    scene_at(@here, description: "The revolver lies on the table where Grenn left it.")
    scene_at(@here, description: "She reads from the daybook without looking up.")

    assert_empty audit.flags
  end

  test "a denial reads like a claim to a regex and is not one" do
    landlord = create(:character, story: @story, fullname: "Grenn Ollivar")
    create(:item, character: landlord, name: "revolver")
    create(:item, character: landlord, name: "pistol")
    create(:item, character: landlord, name: "gun")

    scene_at(@here, description: "There is no revolver, no pistol, no weapon of any kind on your person " \
                                 "-- you left that sort of thinking behind in the marshes.")
    scene_at(@here, description: "You have no gun.")
    scene_at(@here, description: "You reach for the revolver at your hip, but your fingers find only the empty holster.")

    assert_empty audit.flags
  end

  # A place named in prose is not a place claimed as reachable, and there is no
  # check that says otherwise. This test exists to keep one from coming back.
  test "naming another location in prose is never a flag" do
    create(:location, story: @story, name: "Mournwell Lane")
    create(:location, story: @story, name: "The Ever-Shifting Bazaar")
    scene_at(@here, description: "Through the window, Mournwell Lane is a grey seam of roofs, " \
                                 "and the Ever-Shifting Bazaar will be somewhere south of it by dawn.")

    assert_empty audit.flags
  end

  # Same for people: naming somebody who is not here is not a claim that they
  # are, and there is deliberately no check for it. Drift covers the real case.
  test "naming an absent character in prose is never a flag" do
    create(:character, story: @story, fullname: "Grenn Ollivar", nickname: "Old Grenn")
    scene_at(@here, description: "Grenn keeps the front door bolted after the tenth bell, " \
                                 "and his voice comes creaking up the stairwell.")

    assert_empty audit.flags
  end

  test "an item whose row changed after the scene was written is not judged" do
    landlord = create(:character, story: @story, fullname: "Grenn Ollivar")
    scene = scene_at(@here, description: "You reach into your coat and draw your revolver.")
    item = create(:item, character: landlord, name: "revolver")
    item.update!(updated_at: scene.created_at + 1.hour)

    result = audit

    assert_empty result.flags
    assert_equal :item_not_held, result.unjudged.first.code
    assert_match(/changed hands after this scene/, result.unjudged.first.reason)
  end

  # --- drift ---------------------------------------------------------------

  test "drift is reported against the narration the player had just read" do
    scene = scene_at(@here, description: "A cellar door stands open in the far wall.")
    playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
    create(:playthrough_drift, playthrough: playthrough, scene: scene, location: @here,
                               action: "move", command: "go through the cellar door",
                               offered: "The Long Corridor")

    result = audit
    flag = result.drifts.first

    assert_equal 1, result.drifts.size
    assert_equal :reached_for_nothing, flag.code
    assert_equal scene, flag.scene
    assert_match(/tried to move/, flag.headline)
    assert_equal "The Long Corridor", flag.evidence["was offered"]
  end

  # The two are counted separately because they are different claims: one the
  # records prove, one they only witness.
  test "drift is not counted as a contradiction" do
    scene = scene_at(@here, description: "A cellar door stands open in the far wall.")
    playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
    create(:playthrough_drift, playthrough: playthrough, scene: scene, action: "move",
                               command: "go through the cellar door")

    result = audit

    assert_empty result.contradictions
    assert_equal 1, result.drifts.size
    assert_equal "1 scenes: 0 contradictions, 1 drift", result.headline
  end

  test "drift from another story is not this story's drift" do
    scene = scene_at(@here, description: "A cellar door stands open.")
    create(:playthrough_drift, playthrough: create(:playthrough), scene: nil)

    assert_empty audit.drifts
    assert_not_nil scene
  end

  test "a room with nothing on offer says so rather than saying nothing" do
    scene = scene_at(@here, description: "The corridor is empty in both directions.")
    playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
    create(:playthrough_drift, playthrough: playthrough, scene: scene, action: "talk",
                               command: "talk to the clerk", offered: "")

    assert_equal "nothing at all", audit.drifts.first.evidence["was offered"]
  end

  # --- reporting -----------------------------------------------------------

  # Two rows with the same name is a real state; a sentence naming that thing is
  # one claim. Two flags for it would read as a bug in the sweep.
  test "two items with the same name earn one flag, not two" do
    landlord = create(:character, story: @story, fullname: "Grenn Ollivar")
    create(:item, character: landlord, name: "brass stamp")
    create(:item, :lying, location: @there, name: "Brass Stamp")
    scene_at(@here, description: "You put the brass stamp in your coat pocket.")

    assert_equal 1, audit.contradictions.size
  end

  # A table with one evidence column needs each check to name its own best line.
  test "each flag names the one line of evidence that convicts it" do
    landlord = create(:character, story: @story, fullname: "Grenn Ollivar")
    create(:item, character: landlord, name: "revolver")
    connect(@here, create(:location, story: @story, name: "The Stairwell"))
    first = scene_at(@here, description: "You draw your revolver.")
    scene_at(@there, description: "You are somehow in the corridor.", previous: first)

    by_code = audit.contradictions.index_by(&:code)

    assert_equal "You draw your revolver.", by_code[:item_not_held].evidence_line
    assert_equal "exits from Room 3: The Stairwell", by_code[:unreachable_transition].evidence_line
  end

  test "a drift's evidence line is what the player typed" do
    scene = scene_at(@here, description: "A cellar door stands open.")
    playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
    create(:playthrough_drift, playthrough: playthrough, scene: scene, action: "move",
                               command: "go through the cellar door")

    assert_equal "go through the cellar door", audit.drifts.first.evidence_line
  end

  test "tally counts by code, which is the number to watch over time" do
    landlord = create(:character, story: @story, fullname: "Grenn Ollivar")
    create(:item, character: landlord, name: "revolver")
    first = scene_at(@here, description: "You draw your revolver.")
    scene_at(@there, description: "You are somehow in the corridor.", previous: first)

    assert_equal({ unreachable_transition: 1, item_not_held: 1 }, audit.tally)
  end

  test "all reads every story in the database, oldest first" do
    other = create(:story)

    audits = Story::Audit.all

    assert_equal [ @story, other ], audits.map(&:story)
  end

  test "scenes read oldest first, so a report follows the story" do
    connect(@here, @there)
    first = scene_at(@here, description: "The lamp gutters.")
    second = scene_at(@there, description: "The corridor keeps going.", previous: first)

    assert_equal [ first, second ], audit.scenes
  end
end
