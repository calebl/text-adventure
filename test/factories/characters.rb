FactoryBot.define do
  factory :character do
    association :story
    sequence(:fullname) { |n| "Character #{n}" }
    sequence(:nickname) { |n| "Nick#{n}" }
    age { rand(18..100) }
    sex { %w[male female non_binary transgender].sample }
    race { %w[human elf dwarf orc hobbit].sample }
    personality { "Brave and determined with a strong moral compass" }
    appearance { "Average height with distinctive features and weathered clothing" }
    likes { "Adventure, justice, helping others" }
    dislikes { "Cruelty, injustice, unnecessary conflict" }
    fears { "Failing those who depend on them" }
    backstory { "A person with a mysterious past who has seen both joy and hardship" }
    is_companion { false }

    trait :protagonist do
      fullname { "Hero Protagonist" }
      nickname { "Hero" }
      age { 25 }
      sex { "male" }
      race { "human" }
      personality { "Courageous, curious, and kind-hearted despite facing many challenges" }
      appearance { "Young person with determined eyes and simple but practical clothing" }
      backstory { "An ordinary person thrust into extraordinary circumstances" }
      is_companion { false }
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
      race { "elf" }
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
      race { "hobbit" }
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
