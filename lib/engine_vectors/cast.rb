# The seeded cast draws: who each person a realized room is born with is, and
# the details a generated character is handed before its prompt is written.
module EngineVectors::Cast
  SOURCES = [ "app/models/character/registry.rb", "app/models/character/generator.rb", "app/models/location/danger.rb",
              "app/models/location/population.rb", "app/models/character.rb", "app/models/roll.rb" ].freeze
  NOTES = "A room case is Character::Registry#slots for one room of a story whose races are written " \
          "as [name, monstrous] in `races`, holding nobody yet: one slot per person drawn, each " \
          "{race, age, sex}. A generator case is Character::Generator's draws with " \
          "rng = Roll.generator(story:, sequence:, kind: CAST) (sequence is the story's character " \
          "count): race, age and sex, then attractiveness, born_in and raised_by.".freeze

  G = Character::Generator

  RACES = [
    [ [ "Human", false ] ],
    [ [ "Elf", false ], [ "Dwarf", false ], [ "Goblin", true ], [ "Wight", true ] ],
    [ [ "Ghoul", true ] ]
  ].freeze

  def self.constants_table
    {
      "sexes" => Character.sexes.values, "npc_ages" => [ 18, 80 ], "generated_ages" => [ 18, 120 ],
      "attractiveness" => G::ATTRACTIVENESS_VALUES, "birth_places" => G::BIRTH_PLACES, "raised_by" => G::RAISED_BY,
      "max_per_room" => Character::Registry::MAX_PER_ROOM
    }
  end

  def self.cases
    rooms + generators
  end

  def self.rooms
    RACES.each_with_index.flat_map do |races, r|
      Location::DANGERS.keys.product((1..20).to_a).map do |danger, n|
        input = { "story_id" => 4_000 + 100 * r + n, "races" => races, "location_id" => 40_000 + 13 * n,
                  "name" => "The Yard #{n}", "danger" => danger, "population" => Location::Population::LABELS[n % 3] }
        EngineVectors.case_for("room #{r} #{danger} #{n}", input, EngineVectors.rolled_back { slots(input) })
      end
    end
  end

  def self.slots(input)
    story = EngineVectors::World.story!(input["story_id"], races: input["races"])
    room = EngineVectors::World.location!(story, id: input["location_id"], name: input["name"],
                                          danger: input["danger"], population: input["population"])
    Character::Registry.new(room).slots.map { |slot| { "race" => slot[:race].name, "age" => slot[:age], "sex" => slot[:sex] } }
  end

  def self.generators
    RACES.each_with_index.flat_map do |races, r|
      (0...100).map do |n|
        input = { "story_id" => 5_000 + 1_000 * r + n / 10, "races" => races, "sequence" => n % 10 }
        EngineVectors.case_for("generator #{r} #{n}", input, EngineVectors.rolled_back { draws(input) })
      end
    end
  end

  def self.draws(input)
    story = EngineVectors::World.story!(input["story_id"], races: input["races"])
    rng = Roll.generator(story: story.id, sequence: input["sequence"], kind: Roll::CAST)
    generator = G.new(story, rng: rng)
    prompt = generator.instance_variable_get(:@character_generation_prompt)
    { "race" => generator.race.name, "age" => generator.age, "sex" => generator.sex,
      "attractiveness" => prompt[/attractiveness: (.*)$/, 1], "born_in" => prompt[/born in a: (.*)$/, 1],
      "raised_by" => prompt[/raised by: (.*)$/, 1] }
  end
end
