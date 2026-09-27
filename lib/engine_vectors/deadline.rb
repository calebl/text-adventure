# `Quest::Deadline`'s anchor search: which room the engine hangs an overdue
# beat's place off, found by walking the story's doorways.
module EngineVectors::Deadline
  SOURCES = [ "app/models/quest/deadline.rb", "app/models/location.rb" ].freeze
  NOTES = "Each case is one story's rooms and doorways. A room is {id, realized, z, place}; a room with a z is a " \
          "3x3 box at 0,0 on that storey, a place (z null) has a footprint and one child room (id + 1, not connected), so it is laid out. connections " \
          "are [from, to] rows. hops is the private #hops as [id, hops] sorted by id: a breadth-first " \
          "walk from the lowest-id realized room over doorways taken both ways, neighbours in id " \
          "order. anchor is the private #anchor: among reached rooms that are not laid out and have " \
          "fewer than max_exits doorways out, the least [z (null as 0), -hops, id]; null if none.".freeze

  def self.constants_table = { "max_exits" => Location::ExitsSchema::MAX_EXITS, "grace_rooms" => Quest::Deadline::GRACE_ROOMS }

  def self.cases
    (0...200).map do |n|
      input = graph(n)
      EngineVectors.case_for("graph #{n}", input, EngineVectors.rolled_back { search(input) })
    end
  end

  def self.graph(n)
    rng = Random.new(n)
    story_id = 3_000 + n
    ids = (1..(3 + n % 10)).map { |i| story_id * 100 + 2 * i }
    rooms = ids.map do |id|
      { "id" => id, "realized" => n % 7 == 0 ? false : rng.rand(3) > 0, "z" => [ nil, 0, 0, 1, -1, -2, 2 ][rng.rand(7)],
        "place" => rng.rand(6).zero? }.then { |room| room["place"] ? room.merge("z" => nil) : room }
    end
    rows = ids.each_cons(2).select { rng.rand(5) > 0 }.map(&:itself)
    rows += Array.new(rng.rand(ids.size + 1)) { ids.sample(2, random: rng) }
    connections = rows.uniq.reject { |a, b| a == b }.flat_map { |a, b| rng.rand(4).zero? ? [ [ a, b ] ] : [ [ a, b ], [ b, a ] ] }
    { "story_id" => story_id, "rooms" => rooms, "connections" => connections.uniq }
  end

  def self.search(input)
    story = EngineVectors::World.story!(input["story_id"])
    input["rooms"].each do |room|
      shape = if room["place"] then { width: 9, depth: 9 }
      elsif room["z"] then { x: 0, y: 0, z: room["z"], width: 3, depth: 3 }
      else {}
      end
      location = EngineVectors::World.location!(story, id: room["id"], detail_level: room["realized"] ? :realized : :stub, **shape)
      next unless room["place"]

      EngineVectors::World.location!(story, id: room["id"] + 1, parent_location: location, x: 0, y: 0, z: 0, width: 3, depth: 3)
    end
    input["connections"].each { |from, to| EngineVectors::World.connect!(from, to) }
    deadline = Quest::Deadline.new(story)
    { "hops" => deadline.send(:hops).sort.map { |id, hops| [ id, hops ] }, "anchor" => deadline.send(:anchor)&.id }
  end
end
