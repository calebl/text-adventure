FactoryBot.define do
  factory :world_mechanic do
    association :story
    sequence(:name) { |n| "Mechanic #{n}" }
    # The only kind in the catalogue, and the catalogue is code rather than data
    # -- see WorldMechanic::KINDS.
    kind { "shuffle_connections" }
    cadence { "nightly" }
    description { "The city rearranges itself when Nocturna floods it at midnight" }
    # Progress rather than world: a freshly seeded mechanic has never run.
    last_run_at { nil }

    trait :hourly do
      cadence { "hourly" }
    end

    trait :weekly do
      cadence { "weekly" }
    end

    # A mechanic that has already been caught up to a moment in the story.
    trait :ran do
      last_run_at { story.start_time + 1.day }
    end
  end
end
