# `Location::Placement`: where in its room a thing or a person stands.
module EngineVectors::Placements
  SOURCES = [ "app/models/location/placement.rb", "app/models/location/spot.rb", "app/models/roll.rb" ].freeze
  NOTES = "Each case places one record in one room. `record` is Item or Character and its id; `game` " \
          "is null for the world layer (Placement.in_the_world) or the playthrough id and its story " \
          "time in seconds (Placement.in_a_game). A room with no box answers x and y null.".freeze

  Playthrough = Struct.new(:id, :story_now)

  def self.constants_table = { "kinds" => EngineVectors.pairs(Location::Placement::KINDS) }

  ROOMS = [
    { "story_id" => 1, "x" => 0, "y" => 0, "z" => 0, "width" => 6, "depth" => 4 },
    { "story_id" => 7, "x" => 3, "y" => 9, "z" => 1, "width" => 3, "depth" => 3 },
    { "story_id" => 42, "x" => 0, "y" => 0, "z" => -1, "width" => 18, "depth" => 12 },
    { "story_id" => 42, "x" => nil, "y" => nil, "z" => nil, "width" => nil, "depth" => nil }
  ].freeze

  GAMES = [ nil, { "playthrough_id" => 1, "story_now" => 0 }, { "playthrough_id" => 5, "story_now" => 1_767_229_200 } ].freeze

  def self.cases
    ROOMS.product(%w[Item Character], (1..25).to_a, GAMES).map do |room, kind, id, game|
      input = { "room" => room, "record" => { "kind" => kind, "id" => id }, "game" => game }
      EngineVectors.case_for("#{kind} #{id} in room #{ROOMS.index(room)}#{" game #{game["playthrough_id"]}" if game}",
                             input, place(room, kind, id, game))
    end
  end

  def self.place(room, kind, id, game)
    location = Location.new(room)
    record = kind.constantize.new(id: id)
    spot = if game
      Location::Placement.in_a_game(location, record,
                                    playthrough: Playthrough.new(game["playthrough_id"], Time.at(game["story_now"]).utc))
    else
      Location::Placement.in_the_world(location, record)
    end
    spot.transform_keys(&:to_s)
  end
end
