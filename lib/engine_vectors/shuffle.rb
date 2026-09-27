# `WorldMechanic::ShuffleConnections`' arrangement choice: which anchored
# room each mobile room's doorway opens onto after a shuffle. Applying it is
# not recorded here.
module EngineVectors::Shuffle
  SOURCES = [ "app/models/world_mechanic/shuffle_connections.rb" ].freeze
  NOTES = "A graph case gives the story id, its locations as [id, mobile] and its connections as " \
          "[from, to] rows in the order they were written (their ids ascend in that order). " \
          "anchor_edges is ShuffleConnections#anchor_edges as [location_id, connected_location_id]. " \
          "arrangements is, for each `at` in epoch seconds, the private choose_arrangement(edges, at): " \
          "the connected location id each anchor edge would take, in edge order, or null when no " \
          "valid arrangement was found. The Array#shuffle it uses is in the roll portion.".freeze

  def self.constants_table = { "attempts" => WorldMechanic::ShuffleConnections::ATTEMPTS, "seed_story_multiplier" => 1_000_003 }

  ATS = [ 1_767_225_600, 1_767_229_200, 1_767_312_000, 1_767_830_400, 0, 3_600 ].freeze

  def self.cases
    (0...60).map do |n|
      input = graph(n)
      EngineVectors.case_for("graph #{n}", input, EngineVectors.rolled_back { choose(input) })
    end
  end

  # Anchored rooms in a line, mobile rooms each hung off one or two of them,
  # and sometimes a mobile room joined to another.
  def self.graph(n)
    story_id = 2_000 + n
    anchored = (1..(2 + n % 4)).map { |i| story_id * 100 + i }
    mobile = (1..(2 + n % 3)).map { |i| story_id * 100 + 50 + i }
    rows = anchored.each_cons(2).flat_map { |a, b| [ [ a, b ], [ b, a ] ] }
    mobile.each_with_index do |room, i|
      targets = [ anchored[(i + n) % anchored.size] ]
      targets << anchored[(i + n + 1) % anchored.size] if (n + i).odd? && anchored.size > 1
      targets.uniq.each { |target| rows.push([ room, target ], [ target, room ]) }
    end
    rows.push([ mobile.first, mobile.last ], [ mobile.last, mobile.first ]) if n % 5 == 0 && mobile.size > 1
    { "story_id" => story_id,
      "locations" => anchored.map { |id| [ id, false ] } + mobile.map { |id| [ id, true ] },
      "connections" => rows.uniq,
      "ats" => ATS }
  end

  def self.choose(input)
    story = EngineVectors::World.story!(input["story_id"])
    input["locations"].each { |id, mobile| EngineVectors::World.location!(story, id: id, mobile: mobile) }
    input["connections"].each { |from, to| EngineVectors::World.connect!(from, to) }
    mechanic = story.world_mechanics.create!(name: "shuffle", kind: "shuffle_connections", cadence: "nightly")
    shuffle = WorldMechanic::ShuffleConnections.new(mechanic)
    edges = shuffle.anchor_edges
    { "anchor_edges" => edges.map { |edge| [ edge.location_id, edge.connected_location_id ] },
      "arrangements" => input["ats"].map { |at| shuffle.send(:choose_arrangement, edges, Time.at(at).utc) } }
  end
end
