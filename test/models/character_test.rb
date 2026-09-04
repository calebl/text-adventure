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

  # NOWHERE ON PURPOSE: the state a seed file asserts with `absent: true`, told
  # apart from the nowhere nobody meant so that `rake game:doctor` can report
  # one and stay quiet about the other.
  test "absent! is nowhere and meant, and reads as such" do
    character = create(:character, story: @story, location: create(:location, story: @story))

    character.absent!

    assert_predicate character, :nowhere?
    assert_predicate character, :absent?
    assert_equal "nowhere on purpose", character.whereabouts
    assert_includes Character.deliberately_absent, character
  end

  # An engine mechanic that brings somebody back is the story's business, and a
  # person standing in a room is not absent from the world.
  test "move_to! a room clears the deliberate absence, and move_to! nil does not" do
    room = create(:location, story: @story)
    character = create(:character, story: @story)
    character.absent!

    character.move_to!(room)
    assert_not_predicate character.reload, :deliberately_absent?

    character.absent!
    character.move_to!(nil)
    assert_predicate character.reload, :deliberately_absent?, "taking somebody off the map does not decide why"
  end

  # Both halves are asked, because the marker and the column can contradict each
  # other and `Story::Doctor` reports that rather than picking a winner.
  test "a marked character standing somewhere is not absent" do
    character = create(:character, story: @story, location: create(:location, story: @story))
    character.update_column(:deliberately_absent, true)

    assert_not_predicate character, :absent?
    assert_predicate character, :deliberately_absent?
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

  # --- the stat block --------------------------------------------------------
  #
  # Two integers and one formula, and the formula is the whole of what the app
  # derives from them. It gains NO ability term now that there are abilities:
  # there is no constitution among the three, `will` is nerve rather than
  # stamina, and the body's capacity is the hit die -- the captain's ruling of
  # 2026-09-04.

  test "a level 1 body holds its whole hit die" do
    Character::HIT_DICE.each do |die|
      assert_equal die, build(:character, story: @story, level: 1, hit_die: die).max_hp
    end
  end

  # `hit_die / 2 + 1` per level after the first -- the die's average rounded up,
  # in integer arithmetic. Written out here rather than recomputed, so a change
  # to the formula has to be a change to a stated number.
  test "each level after the first adds the die's average rounded up" do
    assert_equal 14, build(:character, story: @story, level: 3, hit_die: 6).max_hp   # 6 + 2 * 4
    assert_equal 18, build(:character, story: @story, level: 3, hit_die: 8).max_hp   # 8 + 2 * 5
    assert_equal 28, build(:character, story: @story, level: 4, hit_die: 10).max_hp  # 10 + 3 * 6
  end

  test "somebody with no stat block has no maximum at all" do
    nobody = build(:character, :without_a_stat_block, story: @story)

    assert_not nobody.stat_block?
    assert_nil nobody.max_hp
  end

  test "a hit die outside the three the engine rolls is refused" do
    assert_not build(:character, story: @story, hit_die: 7).valid?
    assert_not build(:character, story: @story, hit_die: 12).valid?
  end

  test "a level outside the declared range is refused" do
    assert_not build(:character, story: @story, level: 0).valid?
    assert_not build(:character, story: @story, level: 21).valid?
  end

  # HALF A BLOCK IS NOT ONE: `#max_hp` needs both, so a row with one column set
  # looks as though the engine can say something about it and cannot.
  test "half a stat block is refused in both directions" do
    assert_not build(:character, story: @story, level: 1, hit_die: nil).valid?
    assert_not build(:character, story: @story, level: nil, hit_die: 8).valid?
    assert build(:character, story: @story, level: nil, hit_die: nil).valid?
  end

  # THE EXPLICIT CALL, deliberately invoked from nowhere -- exactly as
  # `#move_to!` was when it landed. Levels are stored and inert; this is the
  # statement whatever advances them one day will use.
  test "advancing a level raises the maximum and nothing else" do
    character = create(:character, story: @story, level: 1, hit_die: 8)

    character.advance!

    assert_equal 2, character.reload.level
    assert_equal 13, character.max_hp  # 8 + 1 * 5
  end

  # --- the three abilities ---------------------------------------------------
  #
  # The captain's ruling of 2026-09-04, evening: *"let's go with the 3
  # abilities"* -- strength, dexterity, will, and exactly those three.

  test "there are exactly three abilities and they are the captain's three" do
    assert_equal %i[strength dexterity will], Character::ABILITIES
  end

  # THE RANGE IS 3d6's OWN BOUNDS, not a taste, which is why it is stated as a
  # closed range the way `HIT_DICE` is stated as a closed list.
  test "an ability is 3..18, which is what 3d6 rolls" do
    assert_equal (3..18), Character::ABILITY_RANGE
    assert_not build(:character, story: @story, strength: 2).valid?
    assert_not build(:character, story: @story, dexterity: 19).valid?
    assert_not build(:character, story: @story, will: 0).valid?
  end

  # A PARTIAL SET IS NOT A SET, the mirror of `#a_stat_block_is_whole` -- and it
  # is refused in every direction rather than only the obvious one.
  test "a partial set of abilities is refused, and none at all is fine" do
    Character::ABILITIES.each do |ability|
      assert_not build(:character, :without_abilities, story: @story, ability => 12).valid?,
                 "one #{ability} and nothing else should be refused"
    end

    assert build(:character, :without_abilities, story: @story).valid?
  end

  # THE TWO PREDICATES DO NOT MERGE, and this is the test that says so: a body
  # with no abilities still has a maximum, because `#max_hp` reads `#stat_block?`
  # and every `Playthrough::Vitals` row in the database hangs off that.
  test "a body with no abilities still has a stat block and a maximum" do
    nobody = build(:character, :without_abilities, story: @story, level: 2, hit_die: 8)

    assert_predicate nobody, :stat_block?
    assert_not_predicate nobody, :abilities?
    assert_equal 13, nobody.max_hp
  end

  test "abilities with no stat block are still abilities" do
    somebody = build(:character, :without_a_stat_block, story: @story)

    assert_predicate somebody, :abilities?
    assert_not_predicate somebody, :stat_block?
    assert_nil somebody.max_hp
  end

  # NO ABILITY TERM IN THE MAXIMUM, stated as a test so the question is not
  # reopened: the same body with the three abilities at their floor and at their
  # ceiling holds exactly the same number of hit points.
  test "the maximum is the same whatever the abilities say" do
    floor = build(:character, story: @story, level: 3, hit_die: 8, strength: 3, dexterity: 3, will: 3)
    ceiling = build(:character, story: @story, level: 3, hit_die: 8, strength: 18, dexterity: 18, will: 18)

    assert_equal 18, floor.max_hp
    assert_equal floor.max_hp, ceiling.max_hp
  end

  # --- the check kernel ------------------------------------------------------
  #
  # d20-under the ability, with the penalty taken off the TARGET rather than
  # added to the die. One kernel: no modifier, no DC ladder.

  test "a check passes when the die comes up at or below the score" do
    character = build(:character, story: @story, strength: 12)

    assert_predicate character.check(:strength, rng: fixed(12)), :passed?
    assert_predicate character.check(:strength, rng: fixed(1)), :passed?
    assert_predicate character.check(:strength, rng: fixed(13)), :failed?
    assert_predicate character.check(:strength, rng: fixed(20)), :failed?
  end

  # THE PENALTY MOVES THE TARGET AND NOT THE DIE, which is the whole shape of the
  # kernel: the difficulty is a parameter on the thing being tried.
  test "a penalty is taken off the target and the die is untouched" do
    character = build(:character, story: @story, strength: 12)

    result = character.check(:strength, penalty: 4, rng: fixed(10))

    assert_equal 8, result.target
    assert_equal 10, result.die
    assert_predicate result, :failed?
    assert_equal 12, result.score
  end

  # AT A TARGET OF ZERO OR LESS THERE IS NO ROLL. The pass rate is zero for ever,
  # so the engine says the thing cannot be done -- refusal-shaped -- and the
  # generator is left untouched, so asking the impossible does not consume
  # somebody else's die.
  test "an impossible check throws no die at all" do
    character = build(:character, story: @story, strength: 6)
    rng = Roll.generator(story: 1, sequence: 1)
    next_die = Roll.die(20, rng: Roll.generator(story: 1, sequence: 1))

    result = character.check(:strength, penalty: 6, rng: rng)

    assert_predicate result, :impossible?
    assert_nil result.die
    assert_not result.passed?
    assert_not result.failed?
    assert_equal next_die, Roll.die(20, rng: rng)
  end

  # `check strength -> d20(7) <= 12 PASS`, which is what `rake game:mechanics`
  # prints and `rake game:sweep` asserts. One definition of the sentence.
  test "a check reads out as a record" do
    character = build(:character, story: @story, strength: 12)

    assert_equal "strength -> d20(7) <= 12 PASS", character.check(:strength, rng: fixed(7)).to_s
    assert_equal "strength -> d20(15) <= 10 FAIL", character.check(:strength, penalty: 2, rng: fixed(15)).to_s
    assert_equal "strength -> 12 - 12 = 0, IMPOSSIBLE (no roll)",
                 character.check(:strength, penalty: 12, rng: fixed(3)).to_s
  end

  test "somebody with no abilities cannot be checked at all" do
    nobody = build(:character, :without_abilities, story: @story)

    assert_nil nobody.check(:will, rng: fixed(1))
  end

  test "an ability outside the three is refused rather than answered" do
    character = build(:character, story: @story)

    assert_raises(ArgumentError) { character.check(:constitution, rng: fixed(1)) }
    assert_raises(ArgumentError) { character.check(:charisma, rng: fixed(1)) }
  end

  test "a check reads the column it names" do
    character = build(:character, story: @story, strength: 4, dexterity: 11, will: 18)

    assert_equal [ 4, 11, 18 ],
                 Character::ABILITIES.map { |ability| character.check(ability, rng: fixed(1)).score }
  end

  private

  # A generator that always comes up the same face, so a test about the kernel is
  # a test about the kernel and not about `Roll`'s seed.
  def fixed(face)
    Class.new do
      def initialize(face) = @face = face
      def rand(_range) = @face
    end.new(face)
  end
end
