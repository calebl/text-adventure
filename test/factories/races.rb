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

    # ONE OF A UNIVERSE'S MONSTERS. Not defaulted, for the reason a whereabouts
    # is not defaulted on a character: almost every race in almost every world
    # is a people, and a fixture that had to say so would be saying the ordinary
    # thing out loud everywhere. A dangerous room draws its inhabitants from
    # these (`Character::Registry#slots`) and a character of one is hostile by
    # default (`Character.hostile_by_default?`).
    trait :monstrous do
      sequence(:name) { |n| "Monstrous Race #{n}" }
      description { "A thing the world made and did not mean to, and it goes for anybody still carrying a name." }
      monstrous { true }
    end
  end
end
