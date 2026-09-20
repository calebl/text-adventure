FactoryBot.define do
  factory :character do
    association :story
    sequence(:fullname) { |n| "Character #{n}" }
    sequence(:nickname) { |n| "Nick#{n}" }
    age { rand(18..100) }
    sex { Character.sexes.keys.sample }
    # Races are owned by the universe, so pull one from the story's universe
    # rather than inventing a name that would fail validation.
    race { story.universe.races.first || association(:race, universe: story.universe) }
    personality { "Brave and determined with a strong moral compass" }
    appearance { "Average height with distinctive features and weathered clothing" }
    likes { "Adventure, justice, helping others" }
    dislikes { "Cruelty, injustice, unnecessary conflict" }
    fears { "Failing those who depend on them" }
    backstory { "A person with a mysterious past who has seen both joy and hardship" }
    # THE FOUR OBJECTS OF DESIRE AND THE TWO LABELS, DEFAULTED, on exactly the
    # stat block's reasoning below: having none is a state the game is written
    # to REPORT (`rake game:doctor` -> `character_without_desires`), and every
    # character the app itself writes from today has them. A factory with none
    # would make every fixture look like a database older than the columns.
    #
    # FIXED VALUES AND NEVER A SAMPLE, which is this file's standing rule and
    # matters more here than almost anywhere else: `desire_pursuit` is what
    # `Playthrough::Volition::Weights` reads to weight a die, so a factory that
    # picked a label at random would make every test that asserts what somebody
    # DID a lottery, and land the failure on whoever ran the suite next.
    #
    # THE TWO LABELS ARE DELIBERATELY *NOT* DEFAULTED, which is the opposite
    # decision from the four above and is the more important half.
    # `desire_pursuit` is what `Playthrough::Volition` weights a die with, and
    # a label answers no pursuit at all until somebody sets one -- so a fixture
    # NPC stands still exactly as they did before the feature existed, and a
    # test about a room's contents is not quietly sharing that room with
    # somebody who picks things up. `:driven` is the trait for a fixture whose
    # whole subject is acting on their own.
    conscious_desire { "To be paid what they are owed before the week is out" }
    unconscious_desire { "To be asked their opinion by somebody who waits for the answer" }
    recognized_need { "To keep their word, because it is the only thing they have never broken" }
    unrecognized_need { "To walk into the one room they have been going around for years" }
    is_companion { false }
    is_protagonist { false }
    # THE STAT BLOCK IS DEFAULTED, and it is the opposite decision from the
    # whereabouts below -- so it is worth saying why. Nowhere is a state the
    # game is written to handle; having no body is a state the game is written
    # to REPORT (`rake game:doctor` -> `character_without_a_stat_block`), and
    # every character the app itself writes is given one at the moment it is
    # created. A factory with no stat block would make every fixture look like a
    # database older than the columns.
    #
    # A d8 rather than a roll: a factory that rolled would make a test that
    # asserts a maximum flake. `:without_a_stat_block` is the trait for the
    # older-database state.
    level { 1 }
    hit_die { 8 }
    # THE THREE ABILITIES ARE DEFAULTED TOO, on the same reasoning and with the
    # same choice of fixed numbers over a roll: a factory that rolled would make
    # any test asserting a check outcome flake. They are the ordinary middle of
    # 3d6 with enough spread that a d20-under check against one is not the same
    # question as a check against another. `:without_abilities` is the trait for
    # the older-database state, and it is SEPARATE from
    # `:without_a_stat_block` because the two predicates do not merge -- see
    # `Character`'s header.
    strength { 12 }
    dexterity { 10 }
    will { 14 }
    # WHERE THEY ARE is deliberately not defaulted: nowhere is a real state and
    # it is the one a character starts in, so a test that needs somebody
    # standing in a room says `location:` and means it. See Character's header
    # -- `Character.present_in(location)` is the closed set `talk` resolves
    # against, so defaulting it would put people in rooms nobody asked for.

    # STANDING SOMEWHERE IN PARTICULAR IN A ROOM: `characters.x` and
    # `characters.y`, read in the same plane the room's own box is
    # (`Location::Spot`). It carries the room too, because a position needs one
    # -- `Character#a_position_needs_a_room` refuses one on somebody nowhere --
    # which is the one place this factory departs from its "whereabouts are not
    # defaulted" rule, and it departs from it because the trait's whole subject
    # is where in a room somebody is. `:placed` on a location runs 0..6 along x
    # and 0..7 along y, so 2,5 is inside it.
    #
    # FIXED NUMBERS, NEVER ROLLED, for the reason the stat block above is fixed.
    trait :placed do
      location { association :location, :placed, story: instance.story }
      x { 2 }
      y { 5 }
    end

    trait :protagonist do
      fullname { "Hero Protagonist" }
      nickname { "Hero" }
      age { 25 }
      sex { "male" }
      race { story.universe.races.find_by(name: "Human") || association(:race, universe: story.universe, name: "Human") }
      personality { "Courageous, curious, and kind-hearted despite facing many challenges" }
      appearance { "Young person with determined eyes and simple but practical clothing" }
      backstory { "An ordinary person thrust into extraordinary circumstances" }
      is_companion { false }
      is_protagonist { true }
    end

    # A DATABASE OLDER THAN THE COLUMNS. Both nil, because half a block is a row
    # `Character#a_stat_block_is_whole` refuses to save.
    trait :without_a_stat_block do
      level { nil }
      hit_die { nil }
    end

    # A DATABASE OLDER THAN THE ABILITY COLUMNS. All three nil, because a partial
    # set is a row `Character#abilities_are_whole` refuses to save -- and a
    # SEPARATE trait from the one above, because `Character#stat_block?` and
    # `#abilities?` are separate predicates and a fixture has to be able to hold
    # a body with no abilities (which is exactly what a database looks like
    # between the migration and `rake game:backfill_stat_blocks`).
    trait :without_abilities do
      strength { nil }
      dexterity { nil }
      will { nil }
    end

    # A DATABASE OLDER THAN THE DESIRE COLUMNS, and what a world file that
    # leaves somebody without them loads as. A SEPARATE trait from the two
    # above for their reason: `Character#desires?` is its own predicate, and a
    # fixture has to be able to hold a person with a whole body and nothing
    # they want -- which is exactly what a database looks like between the
    # migration and `rake game:backfill_desires`.
    #
    # THE LABELS GO WITH THEM, because the two arrive in one generated answer
    # and there is no state in which a row got one half and not the other from
    # a generator. A file may still write a label alone; set it by hand where
    # a test wants that.
    trait :without_desires do
      conscious_desire { nil }
      unconscious_desire { nil }
      recognized_need { nil }
      unrecognized_need { nil }
      desire_pursuit { nil }
      need_pursuit { nil }
    end

    # SOMEBODY THE ENGINE HAS SOMETHING TO WEIGHT A DIE WITH: the state a
    # generated or seeded person is in, and the one a test about
    # `Playthrough::Volition` wants. `obtain` and `reach` deliberately differ,
    # because a character whose two labels agree is a character not in conflict
    # and the case worth a fixture is the one where they pull apart.
    trait :driven do
      desire_pursuit { "obtain" }
      need_pursuit { "reach" }
    end

    # SOMEBODY WHOSE CONSCIOUS DESIRE AND UNRECOGNIZED NEED HAVE THE SAME
    # SHAPE: a character not in conflict, which some people should be.
    trait :undivided do
      desire_pursuit { "keep" }
      need_pursuit { "keep" }
    end

    # THE WHOLE SHEET MISSING: what every character in a database older than
    # both migrations has.
    trait :without_a_sheet do
      without_a_stat_block
      without_abilities
      without_desires
    end

    # A MONSTER, and it is an ordinary character with one column set -- which is
    # the whole argument for the flag over a subclass, said as a factory trait.
    # The race comes with it, because hostility is DERIVED from a monstrous race
    # for everybody the engine writes and a hostile person of one of the world's
    # peoples would be a fixture that quietly disagreed with
    # `Character.hostile_by_default?`. Use `hostile { true }` on its own for the
    # one case a seed file can also author: a hostile person of a people.
    #
    # THE NINE FIELDS ARE NOT RELAXED, and this trait fills none of them in
    # differently: a monster has a backstory and a sheet and something it is
    # afraid of, because every one of those is interpolated into
    # `#interaction_instructions` and a monster you can talk to is a feature.
    trait :monster do
      race { story.universe.races.monstrous.first || association(:race, :monstrous, universe: story.universe) }
      hostile { true }
    end

    # A FOE WITH NO BODY -- what a database older than the stat block columns
    # holds and what `rake game:doctor` reports as `hostile_without_a_stat_block`.
    # `WorldSeed::Loader#validate_hostility!` refuses a FILE that says this, so
    # the state only exists in an old database or a fixture like this one.
    trait :monster_without_a_stat_block do
      monster
      without_a_stat_block
    end

    # NOWHERE ON PURPOSE: what a seed file asserts with `absent: true`. Not the
    # same as the default nowhere above -- that one is the state nobody has
    # decided, and `rake game:doctor` reports it.
    trait :absent do
      location { nil }
      deliberately_absent { true }
    end

    trait :companion do
      is_companion { true }
      personality { "Loyal, supportive, and ready to face danger alongside friends" }
      backstory { "A trusted ally who has chosen to join the protagonist's quest" }
    end

    trait :villain do
      personality { "Cunning, ruthless, and driven by dark ambitions" }
      appearance { "Imposing figure with cold eyes and an aura of menace" }
      likes { "Power, control, fear" }
      dislikes { "Weakness, compassion, heroes" }
      fears { "Losing power, being defeated" }
      backstory { "Once perhaps good, but corrupted by power and dark influences" }
    end

    trait :wise_mentor do
      age { rand(60..200) }
      personality { "Wise, patient, and knowledgeable with deep understanding of ancient lore" }
      appearance { "Elderly figure with kind eyes and robes that have seen many journeys" }
      likes { "Knowledge, teaching, preserving wisdom" }
      dislikes { "Ignorance, haste, the loss of ancient knowledge" }
      backstory { "A learned individual who has studied the mysteries of the world" }
    end

    # Specific character examples
    trait :elrond do
      fullname { "Elrond Half-elven" }
      nickname { "Lord Elrond" }
      age { 6500 }
      sex { "male" }
      race { story.universe.races.find_by(name: "Elf") || association(:race, universe: story.universe, name: "Elf") }
      personality { "Wise, kind, and noble with deep knowledge of ancient lore" }
      appearance { "Tall and graceful with dark hair and ageless features" }
      likes { "Knowledge, peace, music, the preservation of wisdom" }
      dislikes { "War, the corruption of evil, unnecessary conflict" }
      fears { "The fading of the elves and loss of ancient wisdom" }
      backstory { "Son of Eärendil, one of the greatest elven lords of Middle-earth" }
      is_companion { false }
    end

    trait :frodo do
      fullname { "Frodo Baggins" }
      nickname { "Mr. Frodo" }
      age { 50 }
      sex { "male" }
      race { story.universe.races.find_by(name: "Hobbit") || association(:race, universe: story.universe, name: "Hobbit") }
      personality { "Brave, curious, and kind-hearted despite his burden" }
      appearance { "Small hobbit with curly brown hair and large feet" }
      likes { "Books, adventure, good food, the Shire" }
      dislikes { "Evil, the Ring's influence, conflict" }
      fears { "Failing in his quest, the power of the Ring" }
      backstory { "A hobbit from the Shire chosen to bear the One Ring to its destruction" }
      is_companion { false }
    end
  end
end
