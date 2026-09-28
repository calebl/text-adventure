# `Location::Interior`'s layout decision: the rooms and doorways a place is laid out into.
module EngineVectors::Interior
  SOURCES = [ "app/models/location/interior.rb", "app/models/location/parameters.rb", "app/models/location/danger.rb",
              "app/models/location/kind.rb",
              "app/models/location/box.rb", "app/models/location/generator.rb", "app/models/location_connection.rb" ].freeze
  NOTES = "Each case lays out one place (story id, place id, the place's footprint or null to roll one, " \
          "`below`, parameter picks or null, and, on the later configs, the building's `kind` word and the place's " \
          "`density`) with Interior.lay_out! and reads back what it built. " \
          "rooms are in creation order (index 0 is the entry); danger is what the room was written " \
          "with (Danger.for_a_new_room, then the building's own roll when there are picks); kind is the word " \
          "Location::Kind.deal dealt the room and density the place's. edges are " \
          "[from, to, distance, travel_method] by room index in the order they were written, one per " \
          "direction. The story starts at 2026-01-01 00:00 UTC and holds only this place.".freeze

  I = Location::Interior

  def self.constants_table
    {
      "minimum_side" => I::MINIMUM_SIDE, "storeys" => EngineVectors.plain(I::STOREYS),
      "rooms_per_storey" => EngineVectors.plain(I::ROOMS_PER_STOREY), "basements" => EngineVectors.plain(I::BASEMENTS),
      "footprint_sides" => EngineVectors.plain(I::FOOTPRINT_SIDES), "stairwells" => EngineVectors.plain(I::STAIRWELLS),
      "door_die" => I::DOOR_DIE, "extra_door_share" => I::EXTRA_DOOR_SHARE, "paces_per_minute" => I::PACES_PER_MINUTE,
      "max_exits" => Location::ExitsSchema::MAX_EXITS, "distances" => EngineVectors.pairs(LocationConnection::DISTANCES)
    }
  end

  CONFIGS = [
    { "footprint" => nil, "below" => nil, "picks" => nil },
    { "footprint" => [ 9, 9 ], "below" => nil, "picks" => nil },
    { "footprint" => [ 18, 12 ], "below" => 1, "picks" => nil },
    { "footprint" => [ 4, 20 ], "below" => 2, "picks" => nil },
    { "footprint" => [ 3, 3 ], "below" => 0, "picks" => nil },
    { "footprint" => [ 15, 15 ], "below" => nil, "picks" => Quest::Deadline::PICKS },
    { "footprint" => [ 12, 18 ], "below" => nil,
      "picks" => { "storeys_above" => "two storeys up", "danger" => "dangerous", "hazard" => "flooded",
                   "gradient" => "worse the higher you climb" } },
    { "footprint" => nil, "below" => nil,
      "picks" => { "storeys_below" => "a cellar", "danger" => "uneasy", "hazard" => "silent",
                   "gradient" => "worse the deeper you go" } },
    { "footprint" => [ 16, 14 ], "below" => 1, "picks" => nil, "kind" => "inn", "density" => "lived-in" },
    { "footprint" => nil, "below" => nil, "picks" => { "storeys_above" => "two storeys up", "storeys_below" => "a cellar" },
      "kind" => "tower", "density" => "cluttered" },
    { "footprint" => [ 12, 12 ], "below" => 2, "picks" => nil, "kind" => "warehouse", "density" => nil },
    { "footprint" => [ 10, 10 ], "below" => nil, "picks" => nil, "kind" => "no such building", "density" => "sparse" }
  ].freeze

  def self.cases
    CONFIGS.each_with_index.flat_map do |config, index|
      (1..30).map do |n|
        input = { "story_id" => 100 * (index + 1) + n, "place_id" => 10_000 + 37 * n, "place_name" => "The Hall" }.merge(config)
        EngineVectors.case_for("config #{index} layout #{n}", input, EngineVectors.rolled_back { lay_out(input) })
      end
    end
  end

  def self.lay_out(input)
    story = EngineVectors::World.story!(input["story_id"])
    width, depth = input["footprint"]
    place = EngineVectors::World.location!(story, id: input["place_id"], name: input["place_name"], width: width, depth: depth,
                                                  density: input["density"])
    picks = input["picks"]
    I.lay_out!(place, below: input["below"], parameters: picks && Location::Parameters.from(picks), kind: input["kind"])
    place.reload
    rooms = place.child_locations.order(:id).to_a
    index = rooms.each_with_index.to_h { |room, at| [ room.id, at ] }
    {
      "footprint" => [ place.width, place.depth ],
      "rooms" => rooms.map do |room|
        { "name" => room.name, "x" => room.x, "y" => room.y, "z" => room.z, "width" => room.width, "depth" => room.depth,
          "danger" => room.danger, "hazard" => room.hazard, "hazard_die" => room.hazard_die,
          "kind" => room.kind, "density" => room.density }
      end,
      "edges" => LocationConnection.where(location_id: index.keys).order(:id).map do |edge|
        [ index.fetch(edge.location_id), index.fetch(edge.connected_location_id), edge.distance, edge.travel_method ]
      end
    }
  end
end
