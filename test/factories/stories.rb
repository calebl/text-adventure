FactoryBot.define do
  factory :story do
    association :universe
    title { "The Great Adventure" }
    genre { "fantasy" }
    preface { "In a world of magic and wonder, heroes are born from the most unlikely places..." }
    summary { "An epic tale of good versus evil, friendship and sacrifice" }
    start_time { Time.current }

    trait :fantasy_adventure do
      association :universe, :fantasy
      title { "The Lord of the Rings" }
      genre { "fantasy" }
      preface { "In a hole in the ground there lived a hobbit..." }
      summary { "An epic tale of good versus evil in Middle-earth" }
    end

    trait :mystery do
      association :universe, :modern
      title { "The Case of the Missing Artifact" }
      genre { "mystery" }
      preface { "It was a dark and stormy night when the museum's most prized possession vanished..." }
      summary { "A detective story set in modern times" }
    end

    trait :with_characters do
      after(:create) do |story|
        create_list(:character, 3, story: story)
      end
    end

    trait :with_locations do
      after(:create) do |story|
        create_list(:location, 2, story: story)
      end
    end
  end
end
