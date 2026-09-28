# `Item::Kit.roll`: what stands in a room and what lies about in it, rolled on
# its name from its kind and density.
module EngineVectors::Kits
  SOURCES = [ "app/models/item/kit.rb", "app/models/roll.rb", "lib/world_seed.rb" ].freeze
  NOTES = "Each case is one room's name, kind and density (null when none). things is Item::Kit.roll's " \
          "list in the order it is written: each piece a die of kit_die at or under its share, then what lies " \
          "on or in each piece that came up, then the small stuff at the density's count, no name twice, cut at " \
          "visible. within is the index in the same list of the piece a thing lies on or in. use_kind, " \
          "combustible and readable are the tables' for the name, and description is Item::Kit's line. Every " \
          "die comes from Roll.generator(story: 0, sequence: Zlib.crc32(WorldSeed.natural_key(name)), " \
          "kind: KIT).".freeze

  DENSITIES = [ nil, *Location::Kind::DENSITIES ].freeze

  def self.constants_table
    { "kit_die" => Item::Kit::DIE, "visible" => Item::Kit::VISIBLE, "roll_kind" => Roll::KIT }
  end

  def self.cases
    every_kind = Item::Kit::TABLES.fetch("kinds").keys.product(DENSITIES).map do |kind, density|
      one("The #{kind.capitalize}", kind, density)
    end
    many_names = %w[study forest market].product((1..20).to_a).map do |kind, n|
      one("#{%w[The A An].fetch(n % 4, "")} #{%w[Hall Room Yard Stall].fetch(n % 4)} #{n}".strip, kind, "cluttered")
    end
    every_kind + many_names + [ one("The Reading Room", nil, "lived-in"), one("The Reading Room", "ballroom", "lived-in"),
                                one("the  reading room", "study", "lived-in"), one("The Reading Room", "study", "lots") ]
  end

  def self.one(name, kind, density)
    things = Item::Kit.roll(name: name, kind: kind, density: density)
    EngineVectors.case_for("#{name.inspect} #{kind.inspect} #{density.inspect}",
                           { "name" => name, "kind" => kind, "density" => density },
                           { "key" => Zlib.crc32(WorldSeed.natural_key(name)),
                             "things" => things.map { |thing| thing_document(thing, things) } })
  end

  def self.thing_document(thing, things)
    within = thing.within && things.fetch(thing.within)
    { "name" => thing.name, "tier" => thing.tier, "holds" => thing.holds, "bulk" => thing.bulk,
      "within" => thing.within, "how" => thing.how, "kit_key" => thing.kit_key,
      "use_kind" => Item::Kit::TABLES.fetch("use_kinds").fetch(thing.name, "ordinary"),
      "combustible" => Item::Kit::TABLES.fetch("combustible").include?(thing.name),
      "readable" => Item::Kit::TABLES.fetch("readable").include?(thing.name),
      "description" => Item::Kit.description_of(thing, within) }
  end
end
