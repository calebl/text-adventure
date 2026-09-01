require "test_helper"

class PlaythroughTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @playthrough = build(:playthrough, story: @story)
  end

  test "should be valid with valid attributes" do
    assert @playthrough.valid?
  end

  test "should require a story" do
    @playthrough.story = nil
    assert_not @playthrough.valid?
    assert_includes @playthrough.errors[:story], "must exist"
  end

  test "should generate a token on initialize" do
    assert @playthrough.token.present?
    assert_operator @playthrough.token.length, :>=, 24
  end

  test "should require a token" do
    @playthrough.token = nil
    assert_not @playthrough.valid?
    assert_includes @playthrough.errors[:token], "can't be blank"
  end

  test "should require a unique token" do
    existing = create(:playthrough)
    @playthrough.token = existing.token
    assert_not @playthrough.valid?
    assert_includes @playthrough.errors[:token], "has already been taken"
  end

  test "should generate distinct tokens" do
    tokens = 5.times.map { create(:playthrough).token }
    assert_equal tokens.uniq.length, tokens.length
  end

  test "should allow a character, location and scene from its own story" do
    location = create(:location, story: @story)
    @playthrough.character = create(:character, story: @story)
    @playthrough.current_location = location
    @playthrough.current_scene = create(:scene, story: @story, location: location)

    assert @playthrough.valid?
  end

  test "should be valid with no character, location or scene" do
    assert_nil @playthrough.character
    assert_nil @playthrough.current_location
    assert_nil @playthrough.current_scene
    assert @playthrough.valid?
  end

  test "should reject a character from another story" do
    @playthrough.character = create(:character, story: create(:story))
    assert_not @playthrough.valid?
    assert_includes @playthrough.errors[:character], "must belong to the playthrough's story"
  end

  test "should reject a current location from another story" do
    @playthrough.current_location = create(:location, story: create(:story))
    assert_not @playthrough.valid?
    assert_includes @playthrough.errors[:current_location], "must belong to the playthrough's story"
  end

  test "should reject a current scene from another story" do
    other_story = create(:story)
    @playthrough.current_scene = create(:scene, story: other_story, location: create(:location, story: other_story))
    assert_not @playthrough.valid?
    assert_includes @playthrough.errors[:current_scene], "must belong to the playthrough's story"
  end

  test "should belong to a story" do
    playthrough = create(:playthrough, story: @story)
    assert_equal @story, playthrough.story
    assert_includes @story.playthroughs, playthrough
  end

  test "should reference the protagonist and their position" do
    playthrough = create(:playthrough, :started, story: @story)

    assert playthrough.character.is_protagonist?
    assert_equal @story, playthrough.character.story
    assert_equal @story, playthrough.current_location.story
    assert_includes playthrough.character.playthroughs, playthrough
    assert_includes playthrough.current_location.playthroughs, playthrough
  end

  test "should track the current scene" do
    playthrough = create(:playthrough, :in_scene, story: @story)

    assert_equal playthrough.current_location, playthrough.current_scene.location
    assert_includes playthrough.current_scene.playthroughs, playthrough
  end

  # --- where this playthrough stands on the story's clock ------------------

  test "story_now is the story moment of the scene the player is in" do
    story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    scene = create(:scene, story: story, location: create(:location, story: story),
                           story_timestamp: story.start_time + 3.hours)
    playthrough = create(:playthrough, story: story, current_scene: scene)

    assert_equal story.start_time + 3.hours, playthrough.story_now
  end

  # Per-playthrough rather than story-wide: one world can be played twice, and a
  # second player's progress must not drag the first player's next turn forward.
  test "story_now follows this playthrough rather than the story's high-water mark" do
    story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    location = create(:location, story: story)
    mine = create(:scene, story: story, location: location, story_timestamp: story.start_time + 1.hour)
    create(:scene, story: story, location: location, story_timestamp: story.start_time + 10.days)
    playthrough = create(:playthrough, story: story, current_scene: mine)

    assert_equal story.start_time + 1.hour, playthrough.story_now
    assert_equal story.start_time + 10.days, story.clock
  end

  test "story_now falls back to the story's clock before the first turn" do
    story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    playthrough = create(:playthrough, story: story)

    assert_equal story.start_time, playthrough.story_now
  end

  test "story_time_after costs a turn what its kind costs" do
    story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    playthrough = create(:playthrough, story: story)

    assert_equal story.start_time + 10.minutes, playthrough.story_time_after("conversation")
    assert_equal story.start_time + 5.minutes, playthrough.story_time_after("action")
  end

  test "story_time_after refuses a kind of turn nobody has priced" do
    playthrough = create(:playthrough, story: create(:story))

    assert_raises(KeyError) { playthrough.story_time_after("teleporting") }
  end

  test "should be destroyed with its story" do
    playthrough = create(:playthrough, story: @story)
    @story.destroy

    assert_not Playthrough.exists?(playthrough.id)
  end

  test "should survive its character being destroyed" do
    playthrough = create(:playthrough, :started, story: @story)
    playthrough.character.destroy

    assert_nil playthrough.reload.character_id
  end

  test "should survive its current location being destroyed" do
    playthrough = create(:playthrough, :in_scene, story: @story)
    playthrough.current_location.destroy

    playthrough.reload
    assert_nil playthrough.current_location_id
    assert_nil playthrough.current_scene_id
  end

  # THE TURN LOG. It walks backwards from `current_scene`, so two playthroughs
  # branching off one opening arrival each read their own turns. It lives on the
  # model rather than in the controller because `NarrationJob` renders the same
  # log when it broadcasts a finished turn, and a job has no controller to
  # borrow a private method from.
  test "turn_log walks back from the current scene, oldest first" do
    playthrough = create(:playthrough, :in_scene, story: @story)
    opening = playthrough.current_scene
    second = create(:scene, story: @story, location: playthrough.current_location,
                            description: "Rain starts falling.", previous_scene: opening)
    playthrough.update!(current_scene: second)

    assert_equal [ opening, second ], playthrough.turn_log
  end

  test "turn_log is empty for a playthrough that has not started" do
    assert_empty create(:playthrough, story: @story).turn_log
  end

  test "turn_log reads only this playthrough's turns" do
    opening = create(:scene, :opening, story: @story, location: create(:location, story: @story))
    mine = create(:playthrough, story: @story, current_location: opening.location,
                                current_scene: create(:scene, story: @story, location: opening.location,
                                                              description: "I turn left.", previous_scene: opening))
    create(:playthrough, story: @story, current_location: opening.location,
                         current_scene: create(:scene, story: @story, location: opening.location,
                                                       description: "They turn right.", previous_scene: opening))

    assert_equal [ opening.description, "I turn left." ], mine.turn_log.map(&:description)
  end

  # The exits are the move targets `Playthrough::Classifier` will accept, which
  # is why the play page prints them.
  test "exits are the ways out of where the player is standing" do
    playthrough = create(:playthrough, :started, story: @story)
    there = create(:location, story: @story, name: "The Sunken Stair")
    create(:location_connection, location: playthrough.current_location, connected_location: there)

    assert_equal [ there ], playthrough.exits.to_a
  end

  test "exits are empty when the player is nowhere yet" do
    assert_empty create(:playthrough, story: @story).exits
  end
end
