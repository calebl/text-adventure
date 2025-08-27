FactoryBot.define do
  factory :universe do
    physics { "Standard physics with magical exceptions allowing for spells and enchantments" }
    technology { "Medieval level with magical enhancements" }
    weapons { "Swords, bows, staves, and magical implements" }
    races { "Humans, elves, dwarves, orcs, hobbits, wizards" }
    civilizations { "Various kingdoms, elven realms, dwarvish strongholds" }
    geographies { "Diverse landscapes including mountains, forests, rivers, and mystical realms" }
    history { "Ancient wars between good and evil, the forging of rings of power" }
    economics { "Guild-based systems, barter, and coin-based trade" }
    politics { "Feudal kingdoms with councils of wise beings" }
    religion { "Worship of the One, various lesser spirits and nature deities" }

    trait :fantasy do
      # Uses default values above
    end

    trait :modern do
      physics { "Real world physics" }
      technology { "21st century technology" }
      weapons { "Firearms, explosives, modern military equipment" }
      races { "Humans" }
      civilizations { "Modern nation-states and global civilization" }
      geographies { "Earth's geography" }
      history { "Human history as we know it" }
      economics { "Capitalist global economy" }
      politics { "Democratic and authoritarian governments" }
      religion { "Various world religions" }
    end
  end
end
