require "test_helper"

class CharacterTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @character = build(:character,
      story: @story,
      fullname: "Aragorn Dunedain",
      nickname: "Strider",
      age: 35,
      sex: "male",
      personality: "Noble, brave, and determined",
      appearance: "Tall, dark-haired ranger with weathered features",
      likes: "Justice, protecting the innocent",
      dislikes: "Tyranny, evil",
      fears: "Failing those he protects",
      backstory: "A ranger of the north, heir to a lost throne",
      is_companion: false
    )
  end

  test "should be valid with valid attributes" do
    assert @character.valid?
  end

  test "should require fullname" do
    @character.fullname = nil
    assert_not @character.valid?
    assert_includes @character.errors[:fullname], "can't be blank"
  end

  test "should require age" do
    @character.age = nil
    assert_not @character.valid?
    assert_includes @character.errors[:age], "can't be blank"
  end

  test "should require positive age" do
    @character.age = -1
    assert_not @character.valid?
    assert_includes @character.errors[:age], "must be greater than 0"
  end

  test "should require sex" do
    @character.sex = nil
    assert_not @character.valid?
    assert_includes @character.errors[:sex], "can't be blank"
  end

  test "should validate sex inclusion" do
    assert_raises(ArgumentError) do
      @character.sex = "invalid"
    end
  end

  test "should accept valid sex values" do
    %w[male female non_binary transgender].each do |sex|
      @character.sex = sex
      assert @character.valid?, "#{sex} should be valid"
    end
  end

  test "should require race" do
    @character.race = nil
    assert_not @character.valid?
    assert_includes @character.errors[:race], "must exist"
  end

  test "should belong to a race from its own universe" do
    assert @character.valid?
    assert_equal @story.universe, @character.race.universe
  end

  # A race from another universe would silently contradict the setting.
  test "should reject a race from a different universe" do
    @character.race = create(:race)

    assert_not @character.valid?
    assert_includes @character.errors[:race], "must belong to the story's universe"
  end

  test "should require personality" do
    @character.personality = nil
    assert_not @character.valid?
    assert_includes @character.errors[:personality], "can't be blank"
  end

  test "should require appearance" do
    @character.appearance = nil
    assert_not @character.valid?
    assert_includes @character.errors[:appearance], "can't be blank"
  end

  test "should require likes" do
    @character.likes = nil
    assert_not @character.valid?
    assert_includes @character.errors[:likes], "can't be blank"
  end

  test "should require dislikes" do
    @character.dislikes = nil
    assert_not @character.valid?
    assert_includes @character.errors[:dislikes], "can't be blank"
  end

  test "should require fears" do
    @character.fears = nil
    assert_not @character.valid?
    assert_includes @character.errors[:fears], "can't be blank"
  end

  test "should require backstory" do
    @character.backstory = nil
    assert_not @character.valid?
    assert_includes @character.errors[:backstory], "can't be blank"
  end

  test "should default is_companion to false" do
    character = Character.new
    assert_equal false, character.is_companion
  end

  test "should belong to story" do
    assert_equal @story, @character.story
  end

  test "should have many interactions" do
    @character.save!
    location = create(:location, story: @story)
    scene = create(:scene, story: @story, location: location)
    interaction = create(:interaction, character: @character, scene: scene, location: location)
    assert_includes @character.interactions, interaction
  end

  test "should have many items" do
    @character.save!
    item = create(:item, :weapon, character: @character)
    assert_includes @character.items, item
  end

  test "should default is_protagonist to false" do
    character = Character.new
    assert_equal false, character.is_protagonist
  end

  test "should mark the player's character as the protagonist" do
    @character.is_protagonist = true
    assert @character.valid?
    @character.save!
    assert_includes Character.protagonists, @character
    assert_equal @character, @story.protagonist
  end

  test "should allow only one protagonist per story" do
    create(:character, :protagonist, story: @story)
    @character.is_protagonist = true

    assert_not @character.valid?
    assert_includes @character.errors[:is_protagonist],
      "is already set on another character in this story"
  end

  test "should allow a protagonist in each story" do
    create(:character, :protagonist, story: @story)
    other = build(:character, :protagonist, story: create(:story))

    assert other.valid?
  end

  test "should allow the existing protagonist to be saved again" do
    protagonist = create(:character, :protagonist, story: @story)
    protagonist.nickname = "Renamed"

    assert protagonist.valid?
    assert protagonist.save
  end

  test "should have many playthroughs" do
    @character.save!
    playthrough = create(:playthrough, story: @story, character: @character)
    assert_includes @character.playthroughs, playthrough
  end

  test "should have and belong to many scenes" do
    @character.save!
    location = create(:location, story: @story)
    scene = create(:scene, story: @story, location: location)
    @character.scenes << scene
    assert_includes @character.scenes, scene
    assert_includes scene.characters, @character
  end
end
