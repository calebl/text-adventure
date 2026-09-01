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
  #
  # NOTE what is NOT the test for "this candidate moves something": `candidate
  # != current` compares two ARRAYS, and an array can differ while the graph it
  # describes does not. `settle` puts every candidate into the one form that
  # says what it means, and `valid?` then judges it on adjacency.
  def choose_arrangement(edges, at)
    current = edges.map(&:connected_location_id)
    random = Random.new(seed_for(at))
    current_pairs = induced_pairs(edges, current)

    ATTEMPTS.times do
      candidate = settle(edges, current, current.shuffle(random: random))
      next unless valid?(edges, candidate, current_pairs)

      return candidate
    end

    nil
  end

  def seed_for(at)
    # Plain arithmetic on two integers, for the reason in the class comment.
    story.id * 1_000_003 + at.to_i
  end

  # Rewrites an arrangement into the one form that says what it means, WITHOUT
  # changing the graph it describes: within a single mobile location's own
  # edges, an endpoint that location keeps stays on the edge that already had
  # it, and only the endpoints genuinely arriving go on the edges left over.
  #
  # This is sound because reordering endpoints among one location's own edges
  # cannot change which places end up joined -- the induced adjacency, every
  # location's degree, and connectivity all read the same either way -- so
  # `valid?` judges exactly the graph that gets written. What it buys is that a
  # doorway which did not move is no longer counted as a move, and so is no
  # longer reported as one. Without it, a lane with two edges out into the fixed
  # city could have them swapped with each other and be announced twice over as
  # having moved, while a player standing in it sees the same two ways out.
  def settle(edges, current, candidate)
    settled = candidate.dup

    edges.each_index.group_by { |index| edges[index].location_id }.each_value do |indices|
      arriving = indices.map { |index| candidate[index] }
      kept = {}

      indices.each do |index|
        # `index`, not `delete`, so a candidate that named one endpoint twice
        # keeps both occurrences to be caught by `valid?`.
        found = arriving.index(current[index])
        next if found.nil?

        arriving.delete_at(found)
        kept[index] = current[index]
      end

      indices.each { |index| settled[index] = kept.fetch(index) { arriving.shift } }
    end

    settled
  end

  # Three things have to hold, and the last two are the promises this mechanic
  # makes.
  #
  # The arrangement is judged by the ADJACENCY it induces -- the set of
  # unordered pairs of places that end up joined -- and not edge by edge. That
  # is the whole difference between the guarantee and a claim of it. Consider a
  # mobile lane with exactly two edges out into the fixed city, and the
  # candidate that swaps them with each other: every edge's endpoint changed,
  # every endpoint is still used exactly once, degree holds, and the world stays
  # whole. The lane opens onto exactly the two places it opened onto before. A
  # per-edge check calls that a rearrangement; a player standing in the lane
  # sees no such thing. So the canonical form of the graph is what gets
  # compared, and a night with nothing but such candidates does nothing at all.
  def valid?(edges, arrangement, current_pairs)
    pairs = induced_pairs(edges, arrangement)
    # Two edges landing on the same pair would collapse into one exit and cost
    # a location a doorway.
    return false if pairs.size != edges.size
    # A night that changes nothing writes nothing.
    return false if pairs == current_pairs

    connected?(edges, arrangement)
  end

  # The affected edges as a set of unordered endpoint pairs: the adjacency this
  # arrangement induces. Unordered because a connection joins two places rather
  # than pointing from one to the other -- it is stored both ways -- so
  # `[ lane, circle ]` and `[ circle, lane ]` are the same fact about the world.
  def induced_pairs(edges, arrangement)
    edges.each_with_index.map { |edge, index| [ edge.location_id, arrangement[index] ].sort }.to_set
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
    # `choose_arrangement` will not hand over an arrangement that moves nothing,
    # so this is a backstop rather than the guarantee -- the guarantee is in
    # `valid?`, on adjacency, where a caller cannot get around it.
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
