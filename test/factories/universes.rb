FactoryBot.define do
  factory :universe do
    physics { "Standard physics with magical exceptions allowing for spells and enchantments" }
    technology { "Medieval level with magical enhancements" }
    weapons { "Swords, bows, staves, and magical implements" }
    civilizations { "Various kingdoms, elven realms, dwarvish strongholds" }
    geographies { "Diverse landscapes including mountains, forests, rivers, and mystical realms" }
    history { "Ancient wars between good and evil, the forging of rings of power" }
    economics { "Guild-based systems, barter, and coin-based trade" }
    politics { "Feudal kingdoms with councils of wise beings" }
    religion { "Worship of the One, various lesser spirits and nature deities" }

    # Every universe needs at least one race -- characters are assigned from
    # this list, so a universe without one cannot produce a valid character.
    # Built through the association so the races belong to *this* universe
    # rather than each spawning a universe of its own.
    transient do
      race_names { [ "Elf", "Dwarf" ] }
    end

    after(:build) do |universe, evaluator|
      evaluator.race_names.each do |name|
        universe.races.new(name: name, description: "A people of this world, known as the #{name}.")
      end
    end

    trait :fantasy do
      # Uses default values above
    end

    trait :modern do
      race_names { [ "Human" ] }
      physics { "Real world physics" }
      technology { "21st century technology" }
      weapons { "Firearms, explosives, modern military equipment" }
      civilizations { "Modern nation-states and global civilization" }
      geographies { "Earth's geography" }
      history { "Human history as we know it" }
      economics { "Capitalist global economy" }
      politics { "Democratic and authoritarian governments" }
      religion { "Various world religions" }
    end
  end
end
