FactoryBot.define do
  # One turn on which the player reached for something the records do not have.
  # See Playthrough::Drift.
  factory :playthrough_drift, class: "Playthrough::Drift" do
    association :playthrough
    action { "move" }
    command { "go through the cellar door" }
    offered { "The Sunken Stair, Ashgate Market" }
    story_timestamp { Time.current }

    trait :talk do
      action { "talk" }
      command { "talk to the woman by the fire" }
      offered { "" }
    end

    trait :take do
      action { "take" }
      command { "pick up the brass key" }
      offered { "" }
    end
  end
end
