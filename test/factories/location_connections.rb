FactoryBot.define do
  # `time_to_travel` is deliberately never set: LocationConnection derives it
  # from the other two in a before_validation, so a factory that set it would
  # be asserting a value the model is about to overwrite.
  #
  # `distance` and `travel_method` are FIXED, and used to be `.sample` off the
  # two tables. Random defaults made every test that reads an edge's values a
  # lottery: `DebugControllerTest` pinned one direction of an edge and left the
  # other to the factory, so 1 run in 35 rolled the same pair for both, the two
  # directions honestly agreed, and an assertion that the view flags a
  # disagreement failed with nothing on the page to flag. It only ever showed
  # up under parallel workers because minitest seeds the global RNG once per
  # run and the position it has reached by the time a test's factories fire
  # depends on how many earlier `rand` calls landed in the same worker -- which
  # is why the failing seed never reproduced it. A test that wants a particular
  # edge says so; the traits below are how to ask for a different one by name.
  #
  # 20 minutes, and that is chosen rather than arbitrary: it is not 5 or 10, so
  # it collides with neither entry in `Scene::TURN_MINUTES` and a turn priced
  # by this edge cannot be mistaken for a beat in the room (see
  # `Playthrough::Debug#cost_reading_for`).
  factory :location_connection do
    association :location
    association :connected_location, factory: :location
    distance { "across the district" }
    travel_method { "walking" }

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
