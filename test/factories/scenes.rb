FactoryBot.define do
  factory :scene do
    association :story
    association :location
    description { "You find yourself in an intriguing location, filled with possibilities" }
    story_timestamp { Time.current }
    summary { nil }
    previous_scene { nil }

    trait :with_summary do
      summary { "The protagonist explores a new area and discovers important information" }
    end

    trait :with_previous do
      previous_scene { association :scene, strategy: :build }
    end

    trait :with_characters do
      after(:create) do |scene|
        characters = create_list(:character, 2, story: scene.story)
        scene.characters = characters
      end
    end

    # Specific scene examples
    trait :rivendell_arrival do
      description { "You arrive at the gates of Rivendell as the sun sets behind the mountains" }
      summary { "The protagonist arrives at Rivendell" }
    end

    trait :museum_entrance do
      description { "You stand in the grand entrance hall of the museum, marble columns rising high above" }
      summary { "The detective begins investigating at the museum" }
    end

    trait :first_scene do
      description { "Your adventure begins in a place both familiar and strange" }
      story_timestamp { 1.day.ago }
      previous_scene { nil }
    end

    trait :continuing_scene do
      description { "The story continues as new mysteries unfold" }
      story_timestamp { Time.current }
    end
  end
end
