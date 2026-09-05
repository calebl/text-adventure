require "test_helper"

class UniverseTest < ActiveSupport::TestCase
  def setup
    @universe = build(:universe)
  end

  test "should be valid with valid attributes" do
    assert @universe.valid?
  end

  test "should require physics" do
    @universe.physics = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:physics], "can't be blank"
  end

  test "should require technology" do
    @universe.technology = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:technology], "can't be blank"
  end

  test "should require weapons" do
    @universe.weapons = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:weapons], "can't be blank"
  end

  test "should require at least one race" do
    @universe.races = []
    assert_not @universe.valid?
    assert_includes @universe.errors[:races], "can't be blank"
  end

  test "should require civilizations" do
    @universe.civilizations = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:civilizations], "can't be blank"
  end

  test "should require geographies" do
    @universe.geographies = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:geographies], "can't be blank"
  end

  test "should require history" do
    @universe.history = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:history], "can't be blank"
  end

  test "should require economics" do
    @universe.economics = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:economics], "can't be blank"
  end

  test "should require politics" do
    @universe.politics = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:politics], "can't be blank"
  end

  test "should require religion" do
    @universe.religion = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:religion], "can't be blank"
  end

  test "should have many stories" do
    @universe.save!
    story = create(:story, universe: @universe, title: "Test Story")
    assert_includes @universe.stories, story
  end

  # This block is re-sent on every downstream call for the life of the world --
  # once per story, once per room, once per character, and once on every turn
  # of every conversation. At the full record it was 58% of every input token
  # the app sent, so each audience gets only the fields it can use.
  test "the full audience is every field, and is the default" do
    universe = create(:universe)

    assert_equal universe.prompt_details, universe.prompt_details(:full)

    %w[physics technology weapons geographies civilizations history economics politics religion].each do |field|
      assert_includes universe.prompt_details, universe.public_send(field)
    end
    assert_includes universe.prompt_details, universe.races_summary
  end

  test "a room gets what the world is made of, not how it is governed" do
    universe = create(:universe)
    details = universe.prompt_details(:place)

    [ :physics, :technology, :geographies, :civilizations ].each do |field|
      assert_includes details, universe.public_send(field)
    end

    [ :politics, :economics, :history, :weapons ].each do |field|
      assert_not_includes details, universe.public_send(field)
    end
  end

  # Names, not descriptions: a room needs to know who lives in this world, not
  # three sentences on each people's temperament.
  test "a room gets race names without their descriptions" do
    universe = create(:universe)
    details = universe.prompt_details(:place)

    assert_includes details, universe.races.first.name
    assert_not_includes details, universe.races.first.description
  end

  # Physics is in here so a character never offers to do something the world
  # does not allow -- the failure that matters most in dialogue.
  test "a speaking character gets the peoples, the powers and the physics" do
    universe = create(:universe)
    details = universe.prompt_details(:dialogue)

    assert_includes details, universe.races.first.name
    assert_includes details, universe.civilizations
    assert_includes details, universe.politics
    assert_includes details, universe.religion
    assert_includes details, universe.physics
  end

  # The race list was 346 of this audience's 930 tokens and went out again on
  # every turn of every conversation, while the speaker's own race and its full
  # description sit in the character sheet directly below it.
  test "a speaking character gets race names without their descriptions" do
    universe = create(:universe)
    details = universe.prompt_details(:dialogue)

    assert_not_includes details, universe.races.first.description
  end

  # Character::Generator states the one race it picked, with its description,
  # immediately below in the same prompt. Listing all of them there is the
  # same information twice.
  test "generating a character skips the race list it is about to be handed" do
    universe = create(:universe)
    details = universe.prompt_details(:character)

    assert_not_includes details, universe.races.first.description
    assert_includes details, universe.history
    assert_includes details, universe.economics
  end

  # Narrating arrival gets the location's own description and lore in the same
  # prompt, and those were generated FROM the :place block -- they already say
  # what this corner of the world looks like and who lives in it. What they do
  # not carry is what the world permits.
  test "arriving somewhere gets what the world allows, not what it looks like" do
    universe = create(:universe)
    details = universe.prompt_details(:scene)

    assert_includes details, universe.physics
    assert_includes details, universe.technology

    [ :geographies, :civilizations, :politics, :history, :economics, :religion, :weapons ].each do |field|
      assert_not_includes details, universe.public_send(field)
    end
    assert_not_includes details, universe.races.first.name
  end

  # If it ever needs a field :place does not have, the split is wrong: a room
  # and the moment of walking into it should not disagree about the world.
  test "the scene audience is a strict subset of the room audience" do
    place = Universe::AUDIENCE_FIELDS.fetch(:place)
    scene = Universe::AUDIENCE_FIELDS.fetch(:scene)

    assert_equal [], scene - place
    assert (place - scene).any?, "an arrival should be cheaper than building the room"
  end

  # If the two ever converge this is one trimmed block with two callers, not
  # audience-specific context. Worth failing loudly rather than drifting.
  test "the room and dialogue audiences are genuinely different" do
    place = Universe::AUDIENCE_FIELDS.fetch(:place)
    dialogue = Universe::AUDIENCE_FIELDS.fetch(:dialogue)

    assert_not_equal place.sort, dialogue.sort
    assert (place - dialogue).any?, "a room should get something a conversation does not"
    assert (dialogue - place).any?, "a conversation should get something a room does not"
  end

  # ------------------------------------------------------------------------
  # CAPTAIN CALL C4, 2026-09-04: *"monstrous races should reach the prompts."*
  # His explicit word, overriding the combat scout's recommendation that they be
  # filtered out of `:dialogue` and given `:place` a separate bestiary field.
  # This is the only model-facing piece of the monsters slice and it changed no
  # prompt template -- only what the existing list contains once a world marks a
  # race monstrous. These tests are the ruling written down, so a later filter
  # cannot land quietly.

  test "a monstrous race is one of the race names both prompt audiences are given" do
    universe = create(:universe)
    universe.races.destroy_all
    create(:race, universe: universe, name: "Ledger-Kept")
    create(:race, :monstrous, universe: universe, name: "Chime-Rot")

    %i[place dialogue].each do |audience|
      assert_includes universe.reload.prompt_details(audience), "Chime-Rot",
                      "the #{audience} prompt no longer names the world's monsters"
    end
  end

  test "the two pools are readers over the same list the prompts are given" do
    universe = create(:universe)
    universe.races.destroy_all
    people = create(:race, universe: universe, name: "Ledger-Kept")
    monster = create(:race, :monstrous, universe: universe, name: "Chime-Rot")

    assert_equal [ people ], universe.peoples.to_a
    assert_equal [ monster ], universe.monstrous_races.to_a
    assert_equal "Chime-Rot, Ledger-Kept", universe.reload.race_names.split(", ").sort.join(", ")
  end

  test "every audience is a subset of the full field list, bar race_names" do
    full = Universe::AUDIENCE_FIELDS.fetch(:full)

    Universe::AUDIENCE_FIELDS.each do |audience, fields|
      assert_equal [], fields - full - [ :race_names ], "#{audience} names a field :full does not"
    end
  end

  test "every audience produces something for every field it names" do
    universe = create(:universe)

    Universe::AUDIENCE_FIELDS.each_key do |audience|
      details = universe.prompt_details(audience)

      assert details.present?
      assert_no_match(/:\s*$/, details.lines.first, "#{audience} rendered an empty field")
    end
  end

  test "an unknown audience raises rather than silently sending nothing" do
    assert_raises(ArgumentError) { create(:universe).prompt_details(:narration) }
  end
end
