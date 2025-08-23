require "test_helper"

class InteractionTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @location = create(:location, :rivendell, story: @story)
    @scene = create(:scene, :first_scene, story: @story, location: @location)
    @character = create(:character, :elrond, story: @story)
    @interaction = build(:interaction,
      character: @character,
      scene: @scene,
      location: @location,
      pre_thought: "A stranger approaches, I wonder what news they bring",
      pre_feeling: "curious and welcoming",
      action: "stepped forward with a warm smile and greeting",
      post_feeling: "pleased to meet a fellow traveler",
      post_thought: "This person seems trustworthy and has an interesting story",
      inner_resolution: "I will offer them shelter and listen to their tales",
      summary: "Elrond welcomes the traveler to Rivendell"
    )
  end

  test "should be valid with valid attributes" do
    assert @interaction.valid?
  end

  test "should require pre_thought" do
    @interaction.pre_thought = nil
    assert_not @interaction.valid?
    assert_includes @interaction.errors[:pre_thought], "can't be blank"
  end

  test "should require pre_feeling" do
    @interaction.pre_feeling = nil
    assert_not @interaction.valid?
    assert_includes @interaction.errors[:pre_feeling], "can't be blank"
  end

  test "should require action" do
    @interaction.action = nil
    assert_not @interaction.valid?
    assert_includes @interaction.errors[:action], "can't be blank"
  end

  test "should require post_feeling" do
    @interaction.post_feeling = nil
    assert_not @interaction.valid?
    assert_includes @interaction.errors[:post_feeling], "can't be blank"
  end

  test "should require post_thought" do
    @interaction.post_thought = nil
    assert_not @interaction.valid?
    assert_includes @interaction.errors[:post_thought], "can't be blank"
  end

  test "should belong to character" do
    assert_equal @character, @interaction.character
  end

  test "should belong to scene" do
    assert_equal @scene, @interaction.scene
  end

  test "should belong to location" do
    assert_equal @location, @interaction.location
  end

  test "should be completed when inner_resolution is present" do
    @interaction.inner_resolution = nil
    assert_not @interaction.completed?

    @interaction.inner_resolution = "I will help this traveler"
    assert @interaction.completed?
  end

  test "should return character name" do
    assert_equal @character.fullname, @interaction.character_name
  end

  test "should scope by character" do
    @interaction.save!

    other_character = create(:character, story: @story, fullname: "Gandalf")
    other_interaction = create(:interaction,
      character: other_character,
      scene: @scene,
      location: @location
    )

    character_interactions = Interaction.for_character(@character)
    assert_includes character_interactions, @interaction
    assert_not_includes character_interactions, other_interaction
  end

  test "should order chronologically" do
    @interaction.save!

    later_interaction = nil
    travel_to(1.hour.from_now) do
      later_interaction = create(:interaction,
        character: @character,
        scene: @scene,
        location: @location,
        summary: "Later interaction"
      )
    end

    chronological = Interaction.chronological
    assert_equal [ @interaction, later_interaction ], chronological.to_a
  end
end
