FactoryBot.define do
  # `time_to_travel` is deliberately never set: LocationConnection derives it
  # from the other two in a before_validation, so a factory that set it would
  # be asserting a value the model is about to overwrite.
  factory :location_connection do
    association :location
    association :connected_location, factory: :location
    distance { LocationConnection::DISTANCES.keys.sample }
    travel_method { LocationConnection::TRAVEL_METHODS.keys.sample }

    trait :short_distance do
      distance { "adjacent" }
      travel_method { "walking" }
    end

    trait :long_distance do
      distance { "days away" }
      travel_method { "riding" }
    end

    trait :indoor_connection do
      distance { "a short walk" }
      travel_method { "taking stairs" }
    end

    trait :dangerous_path do
      distance { "a long journey" }
      travel_method { "crawling" }
    end
  end
end
