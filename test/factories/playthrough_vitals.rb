FactoryBot.define do
  # HOW MUCH IS LEFT OF ONE BODY IN ONE GAME. Full health by default, which is
  # the state an absent row already means -- a factory-made row is for a test
  # that wants the row itself to exist, and `hp_current:` is what a test that
  # cares about the number says.
  factory :playthrough_vitals, class: "Playthrough::Vitals" do
    association :playthrough
    character { association :character, story: playthrough.story }
    hp_current { character.max_hp }

    trait :badly_hurt do
      hp_current { 1 }
    end

    trait :dead do
      hp_current { 0 }
    end
  end
end
