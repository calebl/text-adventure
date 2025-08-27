FactoryBot.define do
  factory :location do
    association :story
    sequence(:name) { |n| "Location #{n}" }
    description { "A mysterious place filled with wonder and potential adventure" }
    lore { "Ancient tales speak of this place and the events that shaped its history" }
    last_protagonist_visit { nil }
    parent_location { nil }

    trait :indoor do
      name { "Ancient Hall" }
      description { "A grand indoor space with high ceilings and echoing footsteps" }
      lore { "Built by craftsmen long ago, this hall has witnessed many important events" }
    end

    trait :outdoor do
      name { "Misty Mountains" }
      description { "Towering peaks shrouded in mist and ancient mystery" }
      lore { "These mountains have stood since the world was young, hiding secrets in their depths" }
    end

    trait :visited do
      last_protagonist_visit { 1.day.ago }
    end

    trait :with_parent do
      parent_location { association :location, strategy: :build }
    end

    # Specific location examples
    trait :rivendell do
      name { "Rivendell" }
      description { "A peaceful elven sanctuary hidden in the mountains, with waterfalls and beautiful architecture" }
      lore { "The Last Homely House East of the Sea, refuge for weary travelers and home to Elrond" }
    end

    trait :shire do
      name { "The Shire" }
      description { "A peaceful land of rolling green hills where hobbits live in comfortable holes" }
      lore { "Home to the halflings, a place of peace and plenty far from the troubles of the world" }
    end

    trait :museum do
      name { "Metropolitan Museum" }
      description { "A grand museum with marble halls filled with priceless artifacts" }
      lore { "One of the city's most prestigious cultural institutions" }
    end

    trait :artifact_room do
      name { "Ancient Artifacts Room" }
      description { "A secured room displaying the museum's most valuable historical pieces" }
      lore { "Where the missing artifact was last seen before its mysterious disappearance" }
    end
  end
end
