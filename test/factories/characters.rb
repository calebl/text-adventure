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
    # WHERE THEY ARE is deliberately not defaulted: nowhere is a real state and
    # it is the one a character starts in, so a test that needs somebody
    # standing in a room says `location:` and means it. See Character's header
    # -- `Character.present_in(location)` is the closed set `talk` resolves
    # against, so defaulting it would put people in rooms nobody asked for.

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
