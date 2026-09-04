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

  # ==========================================================================
  # #interaction_instructions -- the prompt every conversational turn is built
  # on. It is the app's behaviour on the talk path in exactly the way a
  # validation is behaviour elsewhere, so it is pinned the same way.
  # ==========================================================================

  # THE THIRD-PERSON RULE IS SCOPED, and this is the pin. It used to read
  # "Refer to yourself in third person only." two lines under the sentence
  # establishing that quoted text is speech, so it landed on speech too and a
  # character talking aloud was being told to say its own name instead of "I".
  test "the third person rule is gated to the register outside the quotes" do
    prompt = @character.interaction_instructions

    assert_no_match(/Refer to yourself in third person only/, prompt,
                    "the unconditional third-person rule is the defect")

    # The gate itself: naming yourself in the third person appears ONLY in a
    # clause that scopes it to the register outside the quotes, and the clause
    # inside the quotes is the first-person one.
    outside = prompt[/^Outside the quotes.*$/]
    assert_not_nil outside, "third person has to be scoped to the non-quoted register"
    assert_match(/Strider, he, his/, outside)
    assert_match(/^Inside the quotes.*say "I"/, prompt)
  end

  test "speech inside the quotes is first person and never the character's own name" do
    prompt = @character.interaction_instructions

    assert_match(/Inside the quotes you are talking out loud: say "I", never your own name/, prompt)
    assert_match(/Nobody says "Aragorn Dunedain does not know" out loud/, prompt)
  end

  # What the original rule was protecting: the interior fields and the `action`
  # field read as an account OF the character rather than as the character.
  # Scoping the rule keeps that, and says so in one more sentence.
  test "the prompt refuses an account of the character in place of the character" do
    assert_match(/Answer AS Aragorn Dunedain, not about him/,
                 @character.interaction_instructions)
    assert_match(/do not weigh what Strider would probably think/,
                 @character.interaction_instructions)
  end

  # A prompt that named nobody made every NPC invent the person in front of it.
  test "the prompt names the protagonist the character is talking to" do
    @character.save!
    protagonist = create(:character, :protagonist, story: @story, fullname: "Odile Vance", nickname: "Vance")

    prompt = @character.interaction_instructions

    assert_match(/## Who you are talking to/, prompt)
    assert_match(/The person speaking to you is Odile Vance \(Vance\)/, prompt)
    assert_match(/Refer to Odile Vance as #{Regexp.escape(protagonist.pronouns)}/, prompt)
    assert_match(/apparent age: about #{protagonist.age}/, prompt)
    assert_match(/what you can see of them: #{Regexp.escape(protagonist.appearance)}/, prompt)
  end

  # THE PROTAGONIST'S INTERIOR IS THE PLAYER'S OWN, and handing it to every
  # stranger in the world would be a worse bug than the one above. Only what
  # meeting somebody tells you crosses over.
  test "the prompt withholds the protagonist's private interior" do
    @character.save!
    create(:character, :protagonist, story: @story,
           fullname: "Odile Vance",
           backstory: "Falsified a closure order in her second year and has never been asked about it",
           personality: "Patient in the way somebody is patient when they have decided something",
           likes: "A margin wide enough to write in",
           dislikes: "Being thanked for it",
           fears: "That the file she copied is the only one left")

    prompt = @character.interaction_instructions

    [ "Falsified a closure order", "has decided something",
      "A margin wide enough", "Being thanked for it",
      "the only one left" ].each do |private_fact|
      assert_no_match(/#{Regexp.escape(private_fact)}/, prompt,
                      "the protagonist's #{private_fact.inspect} is theirs, not the cast's")
    end
  end

  # A world can be seeded without a protagonist -- see Playthrough::Turn.
  test "the prompt says nothing about an addressee when the story has no protagonist" do
    assert_nil @story.protagonist
    assert_no_match(/## Who you are talking to/, @character.interaction_instructions)
  end

  test "the protagonist is not told who they are talking to" do
    protagonist = create(:character, :protagonist, story: @story)

    assert_no_match(/## Who you are talking to/, protagonist.interaction_instructions)
  end
  # --- the voice, one register per field -----------------------------------

  # THE RULE USED TO SAY that everything outside the quotes is described from
  # outside -- right for the non-speech half of `action`, wrong for the four
  # thought and feeling fields, which the narrator's own example writes in the
  # first person. Now each field is told its register by name.
  test "the voice rule names the register of each field" do
    prompt = @character.interaction_instructions

    assert_match(/pre_thought and post_thought are your private thoughts\. Think them in the first person, as "I"/, prompt)
    assert_match(/pre_feeling and post_feeling are two or three words each/, prompt)
    assert_match(/inner_resolution is what you have decided to do, in the first person/, prompt)
    assert_match(/action is the one field anybody can see/, prompt)
    assert_match(/Speech goes inside quotes, and only speech does/, prompt)
  end

  test "the third-person register outside the quotes uses the determiner, not the possessive pronoun" do
    woman = create(:character, story: @story, fullname: "Mira Halloway", nickname: "Mira", sex: "female")

    assert_match(/^Outside the quotes.*Mira, she, her\./, woman.interaction_instructions)
    assert_no_match(/Mira, she, hers/, woman.interaction_instructions)
  end

  # --- pronoun forms ---------------------------------------------------------

  test "every pronoun set in the table has its forms" do
    assert_equal Character::PRONOUNS.values.uniq.sort, Character::PRONOUN_FORMS.keys.sort
  end

  test "pronoun forms agree verbs with the subject" do
    they = create(:character, story: @story, sex: "non_binary").pronoun_forms
    she = create(:character, story: @story, sex: "female").pronoun_forms

    assert_equal "say", they.agree("says", "say")
    assert_equal "says", she.agree("says", "say")
    assert_equal "their", they.determiner
    assert_equal "theirs", they.possessive
  end
  # --- whereabouts -----------------------------------------------------------
  #
  # `characters.location_id` is the `Item` shape applied to people: one place at
  # a time, owned by the app, and `Character.present_in` is the closed set
  # `talk` resolves against. See the class header.

  test "a character starts nowhere, and nowhere is a legal state" do
    character = create(:character, story: @story)

    assert_predicate character, :nowhere?
    assert_not character.somewhere?
    assert_equal "nowhere", character.whereabouts
    assert_includes Character.nowhere, character
    assert_not_includes Character.somewhere, character
  end

  test "present_in is the closed set for one room, and only that room" do
    here = create(:location, story: @story, name: "The Tide Post")
    there = create(:location, story: @story, name: "The Causeway Court")
    neb = create(:character, story: @story, fullname: "Neb Halloran", location: here)
    brace = create(:character, story: @story, fullname: "Ammon Brace", location: there)
    create(:character, story: @story, fullname: "Nobody At All")

    assert_equal [ neb ], Character.present_in(here).to_a
    assert_equal [ brace ], Character.present_in(there).to_a
    assert_equal "in The Tide Post", neb.whereabouts
    assert_predicate neb, :somewhere?
  end

  test "present_in is ordered by id, so two people in one room are offered stably" do
    here = create(:location, story: @story)
    first = create(:character, story: @story, location: here)
    second = create(:character, story: @story, location: here)

    assert_equal [ first, second ], Character.present_in(here).to_a
  end

  # THE EXPLICIT ENGINE CALL, and the only unconditional one. Nothing in the app
  # invokes it yet, which is the point: movement is a decision.
  test "move_to! moves somebody whether or not they were already somewhere" do
    here = create(:location, story: @story)
    there = create(:location, story: @story)
    character = create(:character, story: @story, location: here)

    character.move_to!(there)
    assert_equal there, character.reload.location

    character.move_to!(nil)
    assert_predicate character.reload, :nowhere?
  end

  # A whereabouts pointing into another world is a row no closed set can offer,
  # because `Character.present_in` is always asked about one story's rooms.
  test "a character cannot stand in another story's room" do
    elsewhere = create(:location, story: create(:story), name: "Somewhere Else Entirely")
    character = build(:character, story: @story, location: elsewhere)

    assert_not character.valid?
    assert_includes character.errors[:location], "must be a place in this story"
  end

  # A person outlives a building: `Location has_many :characters, dependent:
  # :nullify`, so a destroyed room leaves its cast nowhere rather than killing
  # them. `rake game:doctor` reports it.
  test "destroying a room leaves the people in it nowhere" do
    room = create(:location, story: @story)
    character = create(:character, story: @story, location: room)

    room.destroy!

    assert_predicate character.reload, :nowhere?
  end
end
