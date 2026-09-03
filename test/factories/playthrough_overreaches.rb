FactoryBot.define do
  # One turn on which the player named two things the records have and the turn
  # did one of them. See Playthrough::Overreach.
  factory :playthrough_overreach, class: "Playthrough::Overreach" do
    association :playthrough
    action { "take" }
    command { "pickup the index and the apron" }
    acted { "Perrin's private index" }
    unacted { "copy-room apron" }
    story_timestamp { Time.current }

    trait :move do
      action { "move" }
      command { "go to the hallway and then the stairs" }
      acted { "The Long Hallway" }
      unacted { "the stairhead" }
    end

    trait :talk do
      action { "talk" }
      command { "ask Rowe and Lasco where the file went" }
      acted { "Halkett Rowe" }
      unacted { "Perrin Lasco" }
    end
  end
end
