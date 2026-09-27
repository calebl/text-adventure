# `Location::Population`: how many people a room is born with, seeded on its name.
module EngineVectors::Population
  SOURCES = [ "app/models/location/population.rb", "lib/world_seed.rb", "app/models/roll.rb" ].freeze
  NOTES = "Each case is one room's name and stored population label (null when none). natural_key is " \
          "WorldSeed.natural_key(name), key its Zlib CRC32, label the word Population.label_for " \
          "answers (stored if it is one of the labels, otherwise rolled) and count Population.count_for. " \
          "Both dice come from Roll.generator(story: 0, sequence: key, kind: POPULATION).".freeze

  NAMES = [
    "The Market", "the market", "  The   Market  ", "A Tower", "an Inn", "An  Old Inn", "The", "Thebes",
    "Theatre of the Moon", "the\tsunken\ngate", "", "Île Sombre", "the Café Noir", "ANOTHER ROOM",
    "a", "Theatre", "The The", "The Iron Gate Descends"
  ].freeze

  STORED = [ nil, "", "lots", *Location::Population::LABELS ].freeze

  def self.constants_table
    {
      "bands" => EngineVectors.pairs(Location::Population::BANDS),
      "rolled" => Location::Population::ROLLED,
      "leading_article" => WorldSeed::LEADING_ARTICLE.source
    }
  end

  def self.cases
    names = NAMES + (1..300).map { |n| "#{%w[The A An].fetch(n % 4, "")} #{%w[Hall Cellar Market Stair Well].fetch(n % 5)} #{n}".strip }
    cases = names.each_with_index.map { |name, index| one(name, STORED.fetch(index % 2 == 0 ? 0 : index % STORED.size)) }
    cases + NAMES.first(3).product(STORED).map { |name, stored| one(name, stored) }
  end

  def self.one(name, stored)
    location = Location.new(name: name, population: stored)
    rng = Location::Population.generator_for(location)
    EngineVectors.case_for("#{name.inspect} stored #{stored.inspect}", { "name" => name, "population" => stored },
                           { "natural_key" => WorldSeed.natural_key(name),
                             "key" => Location::Population.key_for(location),
                             "label" => Location::Population.label_for(location, rng: rng),
                             "count" => Location::Population.count_for(location) })
  end
end
