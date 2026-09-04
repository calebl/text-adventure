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

  # --- the story's clock ---------------------------------------------------

  test "a story nobody has played is at its own start time" do
    story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))

    assert_equal story.start_time, story.clock
  end

  test "the clock is the latest story moment any scene records" do
    story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    location = create(:location, story: story)
    create(:scene, story: story, location: location, story_timestamp: story.start_time + 20.minutes)
    create(:scene, story: story, location: location, story_timestamp: story.start_time + 4.hours)
    create(:scene, story: story, location: location, story_timestamp: story.start_time + 90.minutes)

    assert_equal story.start_time + 4.hours, story.clock
  end

  # The clock has nothing to do with when anybody had a browser open, which is
  # the whole reason it exists.
  test "the clock does not move with the wall clock" do
    story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))

    travel 3.weeks do
      assert_equal story.start_time, story.clock
    end
  end

  test "another story's scenes are not on this story's clock" do
    story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    other = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    create(:scene, story: other, location: create(:location, story: other),
                   story_timestamp: other.start_time + 10.days)

    assert_equal story.start_time, story.clock
  end

  test "catch_up_world! runs the story's mechanics" do
    story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    mechanic = create(:world_mechanic, story: story)
    create(:scene, story: story, location: create(:location, story: story),
                   story_timestamp: story.start_time + 2.hours)

    story.catch_up_world!

    assert_equal Time.utc(2026, 9, 1, 0, 0, 0), mechanic.reload.last_run_at
  end

  test "should have many world mechanics, destroyed with the story" do
    story = create(:story)
    create(:world_mechanic, story: story)

    assert_difference -> { WorldMechanic.count }, -1 do
      story.destroy
    end
  end

  test "should belong to universe" do
    assert_equal @universe, @story.universe
  end
  # --- what the player starts out holding -------------------------------------
  #
  # World data, not anybody's progress: `characters[].items` under the
  # protagonist in a seed file, held by the protagonist row, carried by nobody.
  # It is the inventory's counterpart of `#opening_location` -- the one thing
  # every playthrough of a world begins from.

  test "the starting inventory is what the protagonist holds" do
    story = create(:story)
    protagonist = create(:character, :protagonist, story: story)
    daybook = create(:item, character: protagonist, name: "Ward Office 12 daybook")

    assert_equal [ daybook ], story.starting_inventory.to_a
  end

  test "what one of the world's own people holds is not the starting inventory" do
    story = create(:story)
    create(:character, :protagonist, story: story)
    landlord = create(:character, story: story, fullname: "Grenn Ollivar")
    create(:item, character: landlord, name: "Iron Ledger")

    assert_empty story.starting_inventory
  end

  # A GENERATED WORLD HAS NONE, and legitimately: only `WorldSeed::Loader` ever
  # writes a protagonist item, so `rake game:new` produces a story whose player
  # starts with empty hands.
  test "a story with no protagonist has no starting inventory rather than raising" do
    assert_empty create(:story).starting_inventory
  end

  test "what a party is carrying is not the starting inventory either" do
    story = create(:story)
    protagonist = create(:character, :protagonist, story: story)
    played = create(:playthrough, story: story, character: protagonist)
    create(:item, :carried, playthrough: played, name: "Brass Key")

    assert_empty story.starting_inventory
  end
end
