FactoryBot.define do
  factory :item do
    association :character
    sequence(:name) { |n| "Item #{n}" }
    description { "A useful object with unknown properties" }
    properties { '{"material": "unknown", "magical": false}' }

    trait :weapon do
      name { "Steel Sword" }
      description { "A well-crafted blade with a sharp edge" }
      properties { '{"damage": 15, "material": "steel", "weapon_type": "sword", "magical": false}' }
    end

    trait :magical_weapon do
      name { "Flaming Sword" }
      description { "A blade wreathed in eternal flames" }
      properties { '{"damage": 25, "material": "enchanted steel", "weapon_type": "sword", "magical": true, "element": "fire"}' }
    end

    trait :armor do
      name { "Leather Armor" }
      description { "Sturdy leather protection for the torso" }
      properties { '{"defense": 8, "material": "leather", "armor_type": "light", "magical": false}' }
    end

    trait :magical_armor do
      name { "Elven Chainmail" }
      description { "Lightweight but incredibly strong armor made by elven smiths" }
      properties { '{"defense": 20, "material": "mithril", "armor_type": "medium", "magical": true, "enchantment": "protection"}' }
    end

    trait :tool do
      name { "Rope" }
      description { "Strong hemp rope, useful for climbing" }
      properties { '{"length": "50 feet", "material": "hemp", "tool_type": "utility", "magical": false}' }
    end

    trait :magical_item do
      name { "Crystal of Light" }
      description { "A glowing crystal that banishes darkness" }
      properties { '{"light_radius": "30 feet", "material": "enchanted crystal", "magical": true, "charges": 10}' }
    end

    trait :consumable do
      name { "Health Potion" }
      description { "A red liquid that restores vitality" }
      properties { '{"healing": 25, "material": "alchemical", "consumable": true, "magical": true}' }
    end

    # Specific item examples
    trait :vilya do
      name { "Vilya" }
      description { "One of the Three Rings of Power, the Ring of Air with a sapphire" }
      properties { '{"power": "preservation", "material": "gold", "gem": "sapphire", "magical": true, "ring_of_power": true}' }
    end

    trait :sting do
      name { "Sting" }
      description { "A small elven blade that glows blue when orcs are near" }
      properties { '{"damage": 12, "material": "elven steel", "weapon_type": "dagger", "magical": true, "orc_detection": true}' }
    end
  end
end
