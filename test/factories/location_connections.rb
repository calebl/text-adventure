FactoryBot.define do
  factory :location_connection do
    association :location
    association :connected_location, factory: :location
    distance { "#{rand(10..200)} miles" }
    time_to_travel { "#{rand(1..10)} days on foot" }
    travel_method { %w[walking horseback boat ship teleportation].sample }

    trait :short_distance do
      distance { "#{rand(1..5)} miles" }
      time_to_travel { "#{rand(30..180)} minutes walking" }
      travel_method { "walking" }
    end

    trait :long_distance do
      distance { "#{rand(100..500)} miles" }
      time_to_travel { "#{rand(7..30)} days travel" }
      travel_method { %w[horseback ship caravan].sample }
    end

    trait :magical_travel do
      distance { "#{rand(500..2000)} miles" }
      time_to_travel { "instant" }
      travel_method { "teleportation" }
    end

    trait :indoor_connection do
      distance { "#{rand(10..100)} meters" }
      time_to_travel { "#{rand(1..5)} minutes" }
      travel_method { "walking through halls" }
    end

    trait :dangerous_path do
      distance { "#{rand(20..100)} miles" }
      time_to_travel { "#{rand(3..14)} days through dangerous terrain" }
      travel_method { "careful travel through hostile lands" }
    end
  end
end
