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
    Character.sexes.each_key do |sex|
      @character.sex = sex
      assert @character.valid?, "#{sex} should be valid"
    end
  end

  # The bug this pins: `transgender` used to be one value with no pronoun rule
  # anywhere, and the generator could roll it. A sex the enum can hold but
  # PRONOUNS cannot answer for is the same bug in a new shape.
  test "every sex the enum can hold has pronouns" do
    assert_equal Character.sexes.keys.sort, Character::PRONOUNS.keys.sort

    Character.sexes.each_key do |sex|
      @character.sex = sex
      assert @character.pronouns.present?, "#{sex} has no pronouns"
    end
  end

  # A sex with no entry raises rather than quietly defaulting to they/them.
  # A silent default is how `transgender` went unnoticed with no rule of its
  # own, they/them-ing people who use she/her or he/him.
  test "pronouns raises for a sex it has no answer for" do
    @character.sex = nil
    assert_raises(KeyError) { @character.pronouns }
  end

  # The captain's rule, and the point of splitting `transgender` in two: a trans
  # woman is a woman and a trans man is a man, so each takes exactly what any
  # other woman or man takes.
  test "a trans woman and a trans man take the same pronouns as any other woman or man" do
    @character.sex = "trans_woman"
    assert_equal "she/her/hers", @character.pronouns
    assert_equal Character::PRONOUNS.fetch("female"), @character.pronouns

    @character.sex = "trans_man"
    assert_equal "he/him/his", @character.pronouns
    assert_equal Character::PRONOUNS.fetch("male"), @character.pronouns
  end

  # `sex` reads back the enum key; anything interpolated into a prompt wants the
  # stored value, which is written to read as English.
  test "sex_label is the stored value, not the enum key" do
    @character.sex = "trans_woman"
    assert_equal "trans woman", @character.sex_label

    @character.sex = "non_binary"
    assert_equal "non-binary", @character.sex_label
  end

  test "the character sheet states the sex in words, not as an enum key" do
    @character.sex = "non_binary"
    assert_match(/sex: non-binary$/, @character.interaction_instructions)
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

  # Two people in one story cannot share a full name -- a player has no other
  # handle on who they are talking to. The captain saw two characters
  # introduced under the same name and this is the record-level guard.
  test "rejects a second character with the same full name in the same story" do
    first = create(:character, fullname: "Ember Lacroix")
    duplicate = build(:character, story: first.story, fullname: "Ember Lacroix")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:fullname], "has already been taken"
  end

  test "compares full names without regard to case" do
    first = create(:character, fullname: "Ember Lacroix")
    duplicate = build(:character, story: first.story, fullname: "ember lacroix")

    assert_not duplicate.valid?
  end

  test "the same full name in a different story is fine" do
    create(:character, fullname: "Ember Lacroix")

    assert build(:character, fullname: "Ember Lacroix").valid?
  end

  # Two people plausibly answer to "Doc" in one story. The full name is the
  # identity; the nickname is not, and constraining it would reject a world
  # that is only being realistic.
  test "two characters in one story may share a nickname" do
    first = create(:character, nickname: "Doc")

    assert build(:character, story: first.story, nickname: "Doc").valid?
  end

  # The validation races; the index is what makes it true when two generations
  # land at once. It is written on LOWER(fullname) so the database enforces
  # exactly what the validation checks.
  test "the database refuses a duplicate full name even past the validation" do
    first = create(:character, fullname: "Ember Lacroix")
    duplicate = build(:character, story: first.story, fullname: "EMBER LACROIX")

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end
end
