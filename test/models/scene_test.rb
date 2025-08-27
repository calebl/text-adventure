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

  test "should have next scene relationship" do
    @scene.save!

    next_scene = @scene.build_next_scene(
      story: @story,
      location: @location,
      description: "You continue your journey",
      story_timestamp: 1.hour.from_now
    )
    next_scene.save!

    assert_equal next_scene, @scene.next_scene
  end

  test "should have and belong to many characters" do
    @scene.save!
    character = create(:character, :elrond, story: @story)

    @scene.characters << character
    assert_includes @scene.characters, character
    assert_includes character.scenes, @scene
  end

  test "should check if has next scene" do
    @scene.save!
    assert_not @scene.has_next_scene?

    next_scene = @scene.build_next_scene(
      story: @story,
      location: @location,
      description: "Next scene",
      story_timestamp: 1.hour.from_now
    )
    next_scene.save!

    @scene.reload
    assert @scene.has_next_scene?
  end

  test "should mark location visit after creation" do
    # Check that location's last_protagonist_visit is updated
    original_visit_time = @location.last_protagonist_visit

    @scene.save!
    @location.reload

    assert_not_equal original_visit_time, @location.last_protagonist_visit
    assert @location.last_protagonist_visit.present?
  end
end
