# `Location::Danger`, its pure half: what a new room is born as, whether a
# person written into a room is a monster, and a building's rooms' danger and hazard.
module EngineVectors::Danger
  SOURCES = [ "app/models/location/danger.rb", "app/models/location/parameters.rb", "app/models/location.rb",
              "app/models/roll.rb" ].freeze
  NOTES = "new_room: Danger.for_a_new_room for a story id, its clock in seconds and how many rooms it " \
          "already has. monstrous: Danger.monstrous? thrown `throws` times in a row on " \
          "Danger.generator_for(room). in_a_place: on Random.new(seed), Danger.in_a_place then " \
          "Danger.hazard_in_a_place for each storey in `storeys` in turn, on one generator; output " \
          "is one {danger, hazard, hazard_die} per storey, hazard and hazard_die null when none.".freeze

  Story = Struct.new(:id, :clock, :locations)
  Rooms = Struct.new(:count)

  def self.constants_table
    {
      "sequence_base" => Location::Danger::SEQUENCE_BASE,
      "rolled" => Location::Danger::ROLLED,
      "dangers" => EngineVectors.pairs(Location::DANGERS),
      "danger_die" => Location::DANGER_DIE,
      "hazard_dice" => Location::HAZARD_DICE
    }
  end

  def self.cases
    new_rooms + monsters + in_a_place
  end

  def self.new_rooms
    [ 1, 7, 42 ].product([ 0, 1_767_225_600 ], (0...40).to_a).map do |story, clock, count|
      input = { "story_id" => story, "clock" => clock, "rooms" => count }
      EngineVectors.case_for("new room #{story}/#{clock}/#{count}", input.merge("kind" => "new_room"),
                             Location::Danger.for_a_new_room(Story.new(story, Time.at(clock).utc, Rooms.new(count))))
    end
  end

  def self.monsters
    Location::DANGERS.keys.product([ 1, 42 ], (1..30).to_a).map do |danger, story, id|
      room = Location.new(id: id, story_id: story, danger: danger)
      rng = Location::Danger.generator_for(room)
      input = { "kind" => "monstrous", "story_id" => story, "location_id" => id, "danger" => danger, "throws" => 4 }
      EngineVectors.case_for("monstrous #{danger} #{story}/#{id}", input,
                             Array.new(4) { Location::Danger.monstrous?(room, rng: rng) })
    end
  end

  PICKS = [
    {},
    { "danger" => "dangerous" },
    { "danger" => "uneasy", "gradient" => "worse the deeper you go", "hazard" => "airless" },
    { "danger" => Location::SAFE, "gradient" => "worse the higher you climb", "hazard" => "silent" },
    { "danger" => "dangerous", "gradient" => "worse the deeper you go", "hazard" => Location::HAZARDS.keys.first }
  ].freeze

  STOREYS = [ 0, 1, 2, -1, -2, 0 ].freeze

  def self.in_a_place
    PICKS.product((0...40).to_a).map do |picks, seed|
      parameters = Location::Parameters.from(picks)
      rng = Random.new(seed)
      output = STOREYS.map do |storey|
        danger = Location::Danger.in_a_place(parameters, storey: storey, rng: rng)
        hazard = Location::Danger.hazard_in_a_place(parameters, storey: storey, rng: rng)
        { "danger" => danger, "hazard" => hazard[:hazard], "hazard_die" => hazard[:hazard_die] }
      end
      EngineVectors.case_for("in a place #{PICKS.index(picks)} seed #{seed}",
                             { "kind" => "in_a_place", "picks" => picks, "seed" => seed, "storeys" => STOREYS }, output)
    end
  end
end
