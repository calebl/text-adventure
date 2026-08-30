require "test_helper"

class StoryTest < ActiveSupport::TestCase
  def setup
    @universe = create(:universe, :fantasy)
    @story = build(:story,
      title: "The Great Adventure",
      genre: "fantasy",
      preface: "In a world of magic and wonder...",
      summary: "A hero's journey begins",
      start_time: Time.current,
      universe: @universe
    )
  end

  test "should be valid with valid attributes" do
    assert @story.valid?
  end

  test "should require title" do
    @story.title = nil
    assert_not @story.valid?
    assert_includes @story.errors[:title], "can't be blank"
  end

  test "should require genre" do
    @story.genre = nil
    assert_not @story.valid?
    assert_includes @story.errors[:genre], "can't be blank"
  end

  test "should require preface" do
    @story.preface = nil
    assert_not @story.valid?
    assert_includes @story.errors[:preface], "can't be blank"
  end

  test "should require summary" do
    @story.summary = nil
    assert_not @story.valid?
    assert_includes @story.errors[:summary], "can't be blank"
  end

  test "should require start_time" do
    @story.start_time = nil
    assert_not @story.valid?
    assert_includes @story.errors[:start_time], "can't be blank"
  end

  test "should have many characters" do
    @story.save!
    character = create(:character, :protagonist, story: @story)
    assert_includes @story.characters, character
  end

  test "should have many locations" do
    @story.save!
    location = create(:location, story: @story, name: "Village Square")
    assert_includes @story.locations, location
  end

  test "should have many scenes" do
    @story.save!
    location = create(:location, story: @story, name: "Village Square")
    scene = create(:scene, story: @story, location: location)
    assert_includes @story.scenes, scene
  end

  test "should have many interactions through characters" do
    @story.save!
    character = create(:character, story: @story)
    interaction = create(:interaction, character: character)
    other_interaction = create(:interaction)

    assert_includes @story.interactions, interaction
    assert_not_includes @story.interactions, other_interaction
  end

  test "destroy removes characters and their interactions without raising" do
    @story.save!
    character = create(:character, story: @story)
    interaction = create(:interaction, character: character)

    assert_nothing_raised { @story.destroy }
    assert_not Character.exists?(character.id)
    assert_not Interaction.exists?(interaction.id)
  end

  test "should have many playthroughs" do
    @story.save!
    playthrough = create(:playthrough, story: @story)
    assert_includes @story.playthroughs, playthrough
  end

  test "should have one protagonist" do
    @story.save!
    assert_nil @story.protagonist

    protagonist = create(:character, :protagonist, story: @story)
    create(:character, story: @story)

    assert_equal protagonist, @story.reload.protagonist
  end

  test "should belong to universe" do
    assert_equal @universe, @story.universe
  end
end
