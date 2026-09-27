# The rows a row-backed portion stands on: a story with explicit ids and a
# fixed start time, so every seed read off it is the same in any database.
module EngineVectors::World
  START = Time.utc(2026, 1, 1)

  UNIVERSE = {
    physics: "Ordinary physics.", technology: "Iron and sail.", weapons: "Blades and bows.",
    civilizations: "Small kingdoms.", geographies: "Hills and coast.", history: "Old wars.",
    economics: "Coin and barter.", politics: "Quarrelling lords.", religion: "Household gods."
  }.freeze

  # `races` is [[name, monstrous], ...] in the order they are written.
  def self.story!(id, races: [ [ "Human", false ] ])
    universe = Universe.new(id: id, **UNIVERSE)
    races.each { |name, monstrous| universe.races.new(name: name, description: "The #{name}.", monstrous: monstrous) }
    universe.save!
    Story.create!(id: id, universe: universe, title: "Vectors #{id}", genre: "fantasy", preface: "A preface.",
                  summary: "A summary.", start_time: START)
  end

  def self.location!(story, id:, name: "Room #{id}", **attributes)
    realized = attributes[:detail_level] == :realized
    story.locations.create!(id: id, name: name, danger: Location::SAFE,
                            **(realized ? { description: "A room.", lore: "Its lore." } : {}), **attributes)
  end

  def self.connect!(from_id, to_id)
    LocationConnection.create!(location_id: from_id, connected_location_id: to_id,
                               distance: LocationConnection::DISTANCES.keys.first, travel_method: Location::Interior::WALKING)
  end
end
