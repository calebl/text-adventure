require "test_helper"

class SceneTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @location = create(:location, :rivendell, story: @story)
    @scene = build(:scene,
      story: @story,
      location: @location,
      description: "You stand at the entrance to Rivendell, marveling at its beauty",
      story_timestamp: Time.current
    )
  end

  test "should be valid with valid attributes" do
    assert @scene.valid?
  end

  test "should require description" do
    @scene.description = nil
    assert_not @scene.valid?
    assert_includes @scene.errors[:description], "can't be blank"
  end

  test "should require story_timestamp" do
    @scene.story_timestamp = nil
    assert_not @scene.valid?
    assert_includes @scene.errors[:story_timestamp], "can't be blank"
  end

  test "should belong to story" do
    assert_equal @story, @scene.story
  end

  test "should belong to location" do
    assert_equal @location, @scene.location
  end

  test "should have optional previous scene" do
    @scene.save!

    next_scene = Scene.new(
      story: @story,
      location: @location,
      description: "You walk deeper into Rivendell",
      story_timestamp: 1.hour.from_now,
      previous_scene: @scene
    )

    assert next_scene.valid?
    assert_equal @scene, next_scene.previous_scene
  end

  # PLURAL. The story's opening arrival belongs to the world, so every
  # playthrough of that story starts on the same Scene and every one of their
  # first moves links back to it -- the forward direction is a branch point, and
  # the `has_one` this replaced would have answered it with whichever
  # playthrough's turn came back first.
  test "should have many next scenes, because a scene can be branched from" do
    @scene.save!

    first = @scene.next_scenes.create!(story: @story, location: @location,
                                       description: "You go left", story_timestamp: 1.hour.from_now)
    second = @scene.next_scenes.create!(story: @story, location: @location,
                                        description: "You go right", story_timestamp: 1.hour.from_now)

    assert_equal [ first, second ], @scene.reload.next_scenes.order(:id).to_a
    assert_equal @scene, first.previous_scene
  end

  # Nothing in `app/` walks forward, but a scene that is destroyed must not
  # leave its successors pointing at a row that is gone.
  test "should nullify next scenes when destroyed" do
    @scene.save!
    following = @scene.next_scenes.create!(story: @story, location: @location,
                                           description: "You continue", story_timestamp: 1.hour.from_now)

    @scene.destroy!

    assert_nil following.reload.previous_scene_id
  end

  test "should have and belong to many characters" do
    @scene.save!
    character = create(:character, :elrond, story: @story)

    @scene.characters << character
    assert_includes @scene.characters, character
    assert_includes character.scenes, @scene
  end

  # Written by the talk branch of the game loop. Nullified rather than
  # destroyed: an Interaction belongs to its character first and to the scene
  # only optionally, so losing the moment must not lose the record of it.
  test "should have many interactions and nullify them when destroyed" do
    @scene.save!
    character = create(:character, story: @story)
    interaction = create(:interaction, character: character, scene: @scene, location: @location)

    assert_includes @scene.interactions, interaction

    @scene.destroy!
    assert_nil interaction.reload.scene_id
  end

  test "should mark location visit after creation" do
    # Check that location's last_protagonist_visit is updated
    original_visit_time = @location.last_protagonist_visit

    @scene.save!
    @location.reload

    assert_not_equal original_visit_time, @location.last_protagonist_visit
    assert @location.last_protagonist_visit.present?
  end

  # THE STORY-TIME HAZARD, closed here.
  #
  # An opening arrival is world data: it is written when the world is BUILT and
  # loaded out of a seed file, which can be weeks before anybody plays. Stamping
  # the visit then would date the protagonist's presence to whenever the file was
  # seeded, and `Scene::Generator` would narrate the player's first walk back
  # into the opening room as a return after however long that was -- the
  # documented wall-clock defect, amplified into something a player reads.
  # Nobody is in the room until a playthrough starts, and
  # PlaythroughsController#create is what says so.
  test "an opening scene does not mark the location as visited" do
    freeze_time do
      travel 3.weeks

      @scene.is_opening = true
      @scene.save!

      assert_nil @location.reload.last_protagonist_visit
    end
  end

  test "a story opens exactly once" do
    @scene.update!(is_opening: true)

    second = build(:scene, :opening, story: @story, location: @location)

    assert_not second.valid?
    assert_includes second.errors[:is_opening], "is already set on another scene in this story"
  end

  test "another story may have its own opening scene" do
    @scene.update!(is_opening: true)

    other = create(:story)
    second = build(:scene, :opening, story: other, location: create(:location, story: other))

    assert second.valid?
  end

  # --- what the turn did ----------------------------------------------------

  test "the resolved action is one of the engine's own actions, or nothing" do
    Scene::ACTIONS.each do |action|
      assert build(:scene, story: @story, location: @location, resolved_action: action).valid?
    end

    assert build(:scene, story: @story, location: @location, resolved_action: nil).valid?

    invented = build(:scene, story: @story, location: @location, resolved_action: "steal")
    assert_not invented.valid?
    assert_includes invented.errors[:resolved_action], "is not included in the list"
  end

  # THE RECORD IS WIDER THAN THE PROMPT, and this is the pair of assertions that
  # says so: a fight is an act the engine takes and no typed word names, so
  # `attack` is recordable without `Playthrough::IntentSchema::INTENTS` -- the
  # closed enum on a model call -- growing by a word.
  test "a scene may record an action the classifier has no word for" do
    scene = build(:scene, story: @story, location: @location, resolved_action: "attack")

    assert scene.valid?
    assert_not_includes Playthrough::IntentSchema::INTENTS, "attack"
  end

  test "engine_authored? is true for every action the engine writes the words of" do
    Scene::ENGINE_AUTHORED.each do |action|
      scene = build(:scene, story: @story, location: @location, resolved_action: action)

      assert_predicate scene, :engine_authored?
    end
  end

  # A THROW IS THE ONE ACTION IN THE GAP THAT IS NOT ENGINE COPY, and it is the
  # reason `ENGINE_AUTHORED` is a named list rather than the difference between
  # `ACTIONS` and `INTENTS`. Its `Scene` is streamed by `Scene::Narrator` off
  # `Playthrough::Turn#thrown_fact`, so skipping it would take real prose out of
  # `Story::Audit`'s reach and shrink `Eval::Richness`'s denominator for nothing.
  test "engine_authored? is false for a throw, which the narrator wrote" do
    scene = build(:scene, story: @story, location: @location, resolved_action: "throw")

    assert scene.valid?
    assert_includes Scene::ACTIONS, "throw"
    assert_not_includes Playthrough::IntentSchema::INTENTS, "throw"
    assert_not_predicate scene, :engine_authored?
  end

  test "engine_authored? is false for every classifier intent, and for no action at all" do
    Playthrough::IntentSchema::INTENTS.each do |action|
      scene = build(:scene, story: @story, location: @location, resolved_action: action)

      assert_not_predicate scene, :engine_authored?
    end

    assert_not_predicate build(:scene, story: @story, location: @location, resolved_action: nil), :engine_authored?
  end

  # WHICH READER ANSWERED, and it is a wider list than what a turn can honestly
  # say: the COLUMN may hold any of `Playthrough::Grammar::PATHS`, and
  # `Scene::TURN_READERS` is what `rake game:doctor` measures a turn against.
  # The two questions are different and the constants are two on purpose.
  test "the reader that resolved the turn is one of the grammar's paths, or nothing" do
    Playthrough::Grammar::PATHS.each do |path|
      assert build(:scene, story: @story, location: @location, resolved_by: path).valid?
    end

    assert build(:scene, story: @story, location: @location, resolved_by: nil).valid?

    invented = build(:scene, story: @story, location: @location, resolved_by: "vibes")

    assert_not invented.valid?
    assert_includes invented.errors[:resolved_by], "is not included in the list"
  end

  test "the readers that write a turn are the two that read a typed line" do
    assert_equal %w[grammar model], Scene::TURN_READERS
    assert_not_includes Scene::TURN_READERS, "engine_view"
  end

  # Three kinds of record out of one reference, which is the closed set the
  # classifier answers from.
  test "the record a turn acted on is a place, a person or a thing" do
    character = create(:character, story: @story)
    item = create(:item, :lying, location: @location)

    assert_equal @location, create(:scene, story: @story, location: @location,
                                           resolved_action: "move", acted_on: @location).acted_on
    assert_equal character, create(:scene, story: @story, location: @location,
                                           resolved_action: "talk", acted_on: character).acted_on
    assert_equal item, create(:scene, story: @story, location: @location,
                                      resolved_action: "take", acted_on: item).acted_on
  end

  # `took?` and `dropped?` are the seams `Story::Audit` trusts outright, so both
  # halves have to be there: an action with no record moved nothing, and a
  # record with the wrong action is a different turn.
  test "a transition needs the action and the record, not either alone" do
    item = create(:item, :lying, location: @location)

    assert_predicate create(:scene, story: @story, location: @location,
                                    resolved_action: "take", acted_on: item), :took?
    assert_not_predicate create(:scene, story: @story, location: @location,
                                        resolved_action: "take", acted_on: nil), :took?
    assert_not_predicate create(:scene, story: @story, location: @location,
                                        resolved_action: "take", acted_on: @location), :took?
    assert_not_predicate create(:scene, story: @story, location: @location,
                                        resolved_action: "drop", acted_on: item), :took?
  end

  test "how a turn read is one line, and nothing at all when nothing is recorded" do
    item = create(:item, :lying, location: @location, name: "Brass Key")
    character = create(:character, story: @story, fullname: "Maren Vosk")

    assert_equal "take -> Brass Key",
                 create(:scene, story: @story, location: @location, resolved_action: "take", acted_on: item).resolution
    assert_equal "talk -> Maren Vosk",
                 create(:scene, story: @story, location: @location, resolved_action: "talk", acted_on: character).resolution
    assert_equal "move -> nothing",
                 create(:scene, story: @story, location: @location, resolved_action: "move").resolution
    assert_nil create(:scene, story: @story, location: @location).resolution
  end
end
