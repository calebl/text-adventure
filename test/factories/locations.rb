FactoryBot.define do
  factory :location do
    association :story
    sequence(:name) { |n| "Location #{n}" }
    # The default is a realized location: a place that has been written out and
    # can be walked into. Use the :stub trait for one that has only been named.
    detail_level { "realized" }
    teaser { "A door stands open onto somewhere you have not been" }
    description { "A mysterious place filled with wonder and potential adventure" }
    lore { "Ancient tales speak of this place and the events that shaped its history" }
    last_protagonist_visit { nil }
    parent_location { nil }
    # Places stay put unless a world says otherwise -- see WorldMechanic.
    mobile { false }
    # And a place is safe unless a world says otherwise -- the column's own
    # default, and what every room already written is. `danger` decides which
    # pool the people BORN here are drawn from (`Character::Registry#slots`), so
    # defaulting it to anything else would put monsters in rooms nobody asked
    # for.
    danger { Location::SAFE }

    # Named by a neighbour and nothing more -- no description, no lore. This is
    # what an unexplored exit looks like until the player walks through it.
    trait :stub do
      detail_level { "stub" }
      description { nil }
      lore { nil }
    end

    trait :realized do
      detail_level { "realized" }
    end

    # A ROOM THAT DRAWS ITS PEOPLE FROM THE WORLD'S BESTIARY. Half the faces of
    # `Location::DANGER_DIE`, which is what `Location::DANGERS` says
    # "dangerous" is; `:deadly` is the one a seed file may say and the engine
    # never rolls.
    trait :dangerous do
      danger { "dangerous" }
    end

    trait :deadly do
      danger { "deadly" }
    end

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

    # A place the world moves at night. What travels is the graph around it: a
    # mobile location's edges out to places that are NOT mobile get repointed.
    trait :mobile do
      mobile { true }
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
