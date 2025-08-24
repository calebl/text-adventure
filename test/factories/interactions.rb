FactoryBot.define do
  factory :interaction do
    association :character
    association :scene
    association :location
    pre_thought { "I wonder what this person wants" }
    pre_feeling { "curious and cautious" }
    action { "approached with a friendly greeting" }
    post_feeling { "satisfied with the interaction" }
    post_thought { "That went better than expected" }
    inner_resolution { nil }
    summary { "Character interacts with someone new" }
    user_input { "Hello there!" }

    trait :completed do
      inner_resolution { "I will help this person with their quest" }
    end

    trait :hostile do
      pre_thought { "This person looks like trouble" }
      pre_feeling { "suspicious and wary" }
      action { "stepped back and demanded to know their business" }
      post_feeling { "vindicated in being cautious" }
      post_thought { "I was right to be suspicious of this stranger" }
      inner_resolution { "I will keep my distance from this person" }
    end

    trait :helpful do
      pre_thought { "This person seems to need assistance" }
      pre_feeling { "compassionate and willing to help" }
      action { "offered aid and guidance" }
      post_feeling { "pleased to be of service" }
      post_thought { "It feels good to help others in need" }
      inner_resolution { "I will continue to help those who need it" }
    end

    trait :mysterious do
      pre_thought { "There is something strange about this encounter" }
      pre_feeling { "intrigued but puzzled" }
      action { "observed carefully while maintaining distance" }
      post_feeling { "more confused than before" }
      post_thought { "There are mysteries here I don't understand" }
      inner_resolution { "I must learn more about what is happening here" }
    end
  end
end
