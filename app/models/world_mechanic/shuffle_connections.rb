# The city moves at night: one endpoint of every edge that joins a MOBILE place
# to an ANCHORED one is repointed, so the same places end up against different
# parts of the world.
#
# EDGE SHUFFLE, not district shuffle, and that is a decision rather than a
# simplification: repointing one endpoint of each affected edge preserves every
# location's degree, so nothing is orphaned and no exit disappears. The variant
# where whole districts travel as units is deliberately not built -- the ruling
# was to play this one and judge the alternative from how it reads.
#
# Which edges move follows from `locations.mobile` alone, and the consequence is
# worth stating because it is what makes the mechanic authorable: an edge whose
# BOTH ends are mobile is never touched. So a building whose rooms are all
# marked mobile travels as one piece with its own doors intact, and only its
# edges out into the fixed city are repointed.
#
# DETERMINISM IS LOAD-BEARING. The permutation comes from a `Random` seeded from
# the story id and the story-time boundary, so the same night shuffles the same
# way in any process, after any restart, forever. Note what is NOT used to build
# that seed: `Array#hash` and `String#hash` are salted per process in Ruby, so
# seeding from one would make the same night shuffle differently after a
# restart -- the exact property this class exists to have.
class WorldMechanic::ShuffleConnections
  # How many permutations to draw before giving the night up. Drawn from the
  # same seeded generator in the same order, so this loop is deterministic too.
  ATTEMPTS = 32

  attr_reader :mechanic

  def initialize(mechanic)
    @mechanic = mechanic
  end

  def story
    mechanic.story
  end

  # Runs one night. Returns the WorldEvent it wrote, or nil when the world did
  # not move -- fewer than two edges to shuffle, or no arrangement that keeps
  # the world whole. A night that changes nothing writes nothing: an event log
  # with entries that mean "nothing happened" is worse than no entry.
  def run!(at)
    edges = anchor_edges
    return nil if edges.size < 2

    arrangement = choose_arrangement(edges, at)
    return nil if arrangement.nil?

    apply!(edges, arrangement, at)
  end

  # One directional row per mobile <-> anchored edge. Exactly one, not two:
  # connections are stored both ways, and the reverse row's `location` is the
  # anchored end, which this scope excludes.
  def anchor_edges
    LocationConnection
      .joins(:location)
      .where(locations: { story_id: story.id, mobile: true })
      .where(connected_location_id: anchored_location_ids)
      .order(:id)
      .to_a
  end

  private

  # An arrangement is the anchored endpoint for each edge, index-aligned with
  # `edges`: a permutation of the endpoints they already have. Permuting rather
  # than choosing freely is what preserves every location's degree.
  def choose_arrangement(edges, at)
    current = edges.map(&:connected_location_id)
    random = Random.new(seed_for(at))

    ATTEMPTS.times do
      candidate = current.shuffle(random: random)
      next if candidate == current
      next unless valid?(edges, candidate)

      return candidate
    end

    nil
  end

  def seed_for(at)
    # Plain arithmetic on two integers, for the reason in the class comment.
    story.id * 1_000_003 + at.to_i
  end

  # Two things have to hold, and the second is the promise this mechanic makes.
  def valid?(edges, arrangement)
    pairs = edges.each_with_index.map { |edge, index| [ edge.location_id, arrangement[index] ] }
    return false if pairs.uniq.size != pairs.size

    connected?(edges, arrangement)
  end

  # Every location in the story still reachable from every other. Degree is
  # preserved by construction, which rules out orphans but not a graph that
  # falls into two halves, so it is checked rather than argued. A breadth-first
  # walk over a few dozen nodes costs nothing.
  def connected?(edges, arrangement)
    ids = location_ids
    return true if ids.size <= 1

    adjacency = adjacency_without(edges)
    edges.each_with_index do |edge, index|
      adjacency[edge.location_id] << arrangement[index]
      adjacency[arrangement[index]] << edge.location_id
    end

    reached = Set.new([ ids.first ])
    frontier = [ ids.first ]
    while (id = frontier.pop)
      adjacency[id].each { |neighbour| frontier << neighbour if reached.add?(neighbour) }
    end

    reached.size == ids.size
  end

  def adjacency_without(edges)
    affected = edges.flat_map { |edge| [ [ edge.location_id, edge.connected_location_id ], [ edge.connected_location_id, edge.location_id ] ] }.to_set
    adjacency = Hash.new { |hash, key| hash[key] = [] }

    LocationConnection.where(location_id: location_ids).pluck(:location_id, :connected_location_id).each do |pair|
      next if affected.include?(pair)

      adjacency[pair.first] << pair.last
    end

    adjacency
  end

  # Repoints the edges and records what happened, in one transaction.
  #
  # Rows are DELETED and rewritten rather than updated in place: the affected
  # endpoints are a permutation of each other, so updating one at a time would
  # transiently collide with the unique index on (location, connected_location).
  # Removing all of them first cannot.
  def apply!(edges, arrangement, at)
    moves = edges.each_with_index.filter_map do |edge, index|
      next if edge.connected_location_id == arrangement[index]

      { edge: edge, from: edge.connected_location_id, to: arrangement[index] }
    end
    return nil if moves.empty?

    # Joins the caller's transaction when there is one (`WorldMechanic#catch_up!`
    # opens one per boundary) and opens its own when `run!` is called directly.
    ActiveRecord::Base.transaction do
      moves.each { |move| remove_edge(move[:edge].location_id, move[:from]) }
      moves.each { |move| write_edge(move[:edge], move[:to]) }

      record!(moves, at)
    end
  end

  def remove_edge(location_id, connected_location_id)
    LocationConnection.where(location_id: location_id, connected_location_id: connected_location_id)
                      .or(LocationConnection.where(location_id: connected_location_id, connected_location_id: location_id))
                      .delete_all
  end

  # The edge keeps its own `distance` and `travel_method`: how far it is from
  # this doorway to whatever the city has put at the end of it is a property of
  # the doorway, not of tonight's neighbour. Both directions, as everywhere
  # else -- LocationConnection's tables are direction-neutral so the same values
  # are correct on the way back.
  def write_edge(edge, connected_location_id)
    values = { distance: edge.distance, travel_method: edge.travel_method }

    [ [ edge.location_id, connected_location_id ], [ connected_location_id, edge.location_id ] ].each do |from, to|
      LocationConnection.create!(location_id: from, connected_location_id: to, **values)
    end
  end

  def record!(moves, at)
    mechanic.world_events.create!(
      story: story,
      occurred_at: at,
      summary: moves.map { |move| sentence_for(move) }.join(" "),
      locations: Location.where(id: moves.flat_map { |move| [ move[:edge].location_id, move[:from], move[:to] ] }.uniq)
    )
  end

  # Written from the MOBILE end, because that is the end a player stands in and
  # those are the exits they read.
  def sentence_for(move)
    "#{name_for(move[:edge].location_id)} now opens onto #{name_for(move[:to])} " \
      "instead of #{name_for(move[:from])}."
  end

  def name_for(id)
    location_names.fetch(id, "somewhere unrecorded")
  end

  def anchored_location_ids
    @anchored_location_ids ||= story.locations.where(mobile: false).pluck(:id)
  end

  def location_ids
    @location_ids ||= story.locations.order(:id).pluck(:id)
  end

  def location_names
    @location_names ||= story.locations.pluck(:id, :name).to_h
  end
end
