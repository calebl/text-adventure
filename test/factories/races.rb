FactoryBot.define do
  factory :race do
    association :universe
    sequence(:name) { |n| "Race #{n}" }
    description { "A people shaped by the land they came from." }

    trait :elf do
      name { "Elf" }
      description { "Long-lived and remote, keepers of the older forests." }
    end

    trait :dwarf do
      name { "Dwarf" }
      description { "Stonewrights of the deep halls, slow to trust and slower to forgive." }
    end
  end
end
