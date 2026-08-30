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
end
