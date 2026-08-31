FactoryBot.define do
  factory :world_event do
    association :world_mechanic
    story { world_mechanic.story }
    occurred_at { story.start_time + 1.hour }
    summary { "Mournwell Lane now opens onto The Celestial Spire instead of Sovereign's Circle." }

    trait :with_locations do
      after(:create) do |event|
        event.locations = create_list(:location, 2, story: event.story)
      end
    end
  end
end
