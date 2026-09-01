require "test_helper"

class WorldMechanic::ShuffleConnectionsTest < ActiveSupport::TestCase
  MIDNIGHT = Time.utc(2026, 9, 1, 0, 0, 0)

  def setup
    @story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    @hub = place("Room 3", mobile: true)
    @movers = [ place("Mournwell Lane", mobile: true), place("The rooftops", mobile: true), place("The hallway", mobile: true) ]
    @anchors = [ place("Sovereign's Circle"), place("The Celestial Spire"), place("The bell tower") ]

    @movers.each { |mover| connect(@hub, mover, distance: "adjacent") }
    @movers.zip(@anchors).each { |mover, anchor| connect(mover, anchor, distance: "across the district") }

    @mechanic = create(:world_mechanic, story: @story, name: "The nightly rearrangement")
  end

  test "only edges from a mobile place to one that is not are candidates" do
    edges = @mechanic.operation.anchor_edges

    assert_equal 3, edges.size
    assert_equal @movers.map(&:id).sort, edges.map(&:location_id).sort
    assert_equal @anchors.map(&:id).sort, edges.map(&:connected_location_id).sort
  end

  test "a night repoints at least two edges" do
    event = @mechanic.operation.run!(MIDNIGHT)

    assert_not_nil event
    assert_equal MIDNIGHT, event.occurred_at
    assert_operator changed_anchors.size, :>=, 2
  end

  # THE PROPERTY THAT MAKES THE EDGE SHUFFLE SAFE: it permutes the endpoints
  # rather than choosing them, so every place keeps exactly the number of ways
  # in and out it had. No exit vanishes and nothing is orphaned.
  test "every location keeps the same number of exits" do
    before = exit_counts

    @mechanic.operation.run!(MIDNIGHT)

    assert_equal before, exit_counts
  end

  test "the world stays connected" do
    @mechanic.operation.run!(MIDNIGHT)

    assert_equal @story.locations.count, reachable_from(@hub).size
  end

  # A building whose rooms are all mobile travels as one piece: an edge with two
  # mobile ends is never touched, so its own doors stay where they were.
  test "an edge between two mobile places is left alone" do
    before = @hub.reload.exits.pluck(:id).sort

    @mechanic.operation.run!(MIDNIGHT)

    assert_equal before, @hub.reload.exits.pluck(:id).sort
  end

  test "both directions of a repointed edge are written" do
    @mechanic.operation.run!(MIDNIGHT)

    LocationConnection.where(location: @story.locations).each do |connection|
      reverse = LocationConnection.find_by(location: connection.connected_location,
                                           connected_location: connection.location)

      assert reverse, "#{connection.location.name} -> #{connection.connected_location.name} has no way back"
      assert_equal connection.distance, reverse.distance
      assert_equal connection.travel_method, reverse.travel_method
    end
  end

  # How far it is from a doorway to whatever the city has put at the end of it is
  # a property of the doorway, so a repointed edge keeps its own values.
  test "a repointed edge keeps its distance and travel method" do
    @mechanic.operation.run!(MIDNIGHT)

    @movers.each do |mover|
      edge = LocationConnection.where(location: mover, connected_location: @anchors).first

      assert_equal "across the district", edge.distance
      assert_equal "walking", edge.travel_method
    end
  end

  # DETERMINISM IS LOAD-BEARING. The same night must shuffle the same way after
  # a restart, so the arrangement is derived from the story id and the boundary
  # and from nothing that lives in a process.
  test "the same night shuffles the same way every time" do
    first = @mechanic.operation.run!(MIDNIGHT).summary
    reset!
    second = @mechanic.operation.run!(MIDNIGHT).summary

    assert_equal first, second
  end

  test "different nights do not all shuffle the same way" do
    arrangements = 6.times.map do |night|
      reset!
      @mechanic.operation.run!(MIDNIGHT + night.days).summary
    end

    assert_operator arrangements.uniq.size, :>, 1, "every night would be the same night"
  end

  test "the event names what moved, from the end the player stands in" do
    event = @mechanic.operation.run!(MIDNIGHT)

    assert_match(/ now opens onto .* instead of /, event.summary)
    changed_anchors.each_key do |mover|
      assert_includes event.summary, mover.name
    end
  end

  test "the event records the places it touched" do
    event = @mechanic.operation.run!(MIDNIGHT)

    moved = changed_anchors
    assert_operator event.locations.count, :>=, moved.size
    moved.each_key { |mover| assert_includes event.locations, mover }
  end

  test "a world with fewer than two shufflable edges does not move" do
    LocationConnection.where(location: @movers.drop(1), connected_location: @anchors).delete_all
    LocationConnection.where(location: @anchors, connected_location: @movers.drop(1)).delete_all
    before = exits_by_name

    assert_nil @mechanic.operation.run!(MIDNIGHT)
    assert_equal before, exits_by_name
    assert_equal 0, @story.world_events.count
  end

  # THE PROMISE, tested on the shape that can actually break it. Preserving every
  # location's degree rules out orphans but NOT a graph that falls into two
  # halves: with an anchor whose only edge is the one being repointed, a
  # permutation can strand it along with the mobile place it was carrying. So
  # connectivity is checked before an arrangement is accepted, and a night with
  # no whole arrangement available does nothing at all.
  test "a night that would split the world in two is refused" do
    story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    a = create(:location, story: story, name: "A", mobile: true)
    b = create(:location, story: story, name: "B", mobile: true)
    c = create(:location, story: story, name: "C", mobile: true)
    x = create(:location, story: story, name: "X")
    y = create(:location, story: story, name: "Y")
    z = create(:location, story: story, name: "Z")

    pairs = [ [ a, b ], [ a, x ], [ b, y ], [ c, z ], [ z, y ] ]
    pairs.each do |from, to|
      [ [ from, to ], [ to, from ] ].each do |origin, destination|
        create(:location_connection, location: origin, connected_location: destination,
                                     distance: "a short walk", travel_method: "walking")
      end
    end

    mechanic = create(:world_mechanic, story: story, name: "The nightly rearrangement")

    # Every night for a fortnight, whatever it decides, the world stays whole.
    14.times do |night|
      mechanic.operation.run!(Time.utc(2026, 9, 1) + night.days)

      reached = Set.new([ a.id ])
      frontier = [ a ]
      while (location = frontier.pop)
        location.reload.exits.each { |exit| frontier << exit if reached.add?(exit.id) }
      end

      assert_equal story.locations.count, reached.size, "night #{night} split the world in two"
    end
  end

  # THE NO-OP CASE, from a real night in a played world: Mournwell Lane's two
  # edges out into the fixed city were swapped with each other. Every per-edge
  # check passes -- each edge's endpoint changed, degree held, the world stayed
  # whole, and the arrangement array is not the one it started with -- but the
  # ADJACENCY is the one it started with. The Lane opens onto both places it
  # opened onto before. Nothing moved, so nothing may be written.
  test "swapping one mobile place's own two edges is not a rearrangement" do
    story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    lane = create(:location, story: story, name: "Mournwell Lane", mobile: true)
    bell = create(:location, story: story, name: "The Bell of Saint Aravel")
    circle = create(:location, story: story, name: "Sovereign's Circle")

    [ [ lane, bell ], [ lane, circle ] ].each do |from, to|
      [ [ from, to ], [ to, from ] ].each do |origin, destination|
        create(:location_connection, location: origin, connected_location: destination,
                                     distance: "across the district", travel_method: "walking")
      end
    end

    mechanic = create(:world_mechanic, story: story, name: "The nightly rearrangement")
    before = lane.reload.exits.pluck(:id).sort

    assert_nil mechanic.operation.run!(MIDNIGHT)
    assert_equal before, lane.reload.exits.pluck(:id).sort
    assert_equal 0, story.world_events.count
  end

  # The same shape, one night after another: no night invents a move, and the
  # log stays empty rather than filling with entries that mean nothing.
  test "a transposable pair of edges writes nothing on any night" do
    story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    lane = create(:location, story: story, name: "Mournwell Lane", mobile: true)
    anchors = [ create(:location, story: story, name: "The Bell of Saint Aravel"),
                create(:location, story: story, name: "Sovereign's Circle") ]

    anchors.each do |anchor|
      [ [ lane, anchor ], [ anchor, lane ] ].each do |origin, destination|
        create(:location_connection, location: origin, connected_location: destination,
                                     distance: "across the district", travel_method: "walking")
      end
    end

    mechanic = create(:world_mechanic, story: story, name: "The nightly rearrangement")

    14.times { |night| assert_nil mechanic.operation.run!(MIDNIGHT + night.days) }
    assert_equal 0, story.world_events.count
  end

  # A sentence in the log is a claim about the graph, so every sentence has to be
  # true OF the graph it was written from. This is the same guarantee as the one
  # above at a finer grain: within one mobile place's own edges, a swap that
  # leaves it opening onto the same places must not be announced as a move even
  # on a night when something else genuinely did move.
  test "every sentence the log writes is true of the graph" do
    story = create(:story, start_time: Time.utc(2026, 8, 31, 23, 0, 0))
    lane = create(:location, story: story, name: "Mournwell Lane", mobile: true)
    others = [ create(:location, story: story, name: "The rooftops", mobile: true),
               create(:location, story: story, name: "The hallway", mobile: true) ]
    anchors = 4.times.map { |n| create(:location, story: story, name: "Anchor #{n}") }

    pairs = [ [ lane, anchors[0] ], [ lane, anchors[1] ],
              [ others[0], anchors[2] ], [ others[1], anchors[3] ],
              [ lane, others[0] ], [ others[0], others[1] ] ]
    pairs.each do |from, to|
      [ [ from, to ], [ to, from ] ].each do |origin, destination|
        create(:location_connection, location: origin, connected_location: destination,
                                     distance: "across the district", travel_method: "walking")
      end
    end

    mechanic = create(:world_mechanic, story: story, name: "The nightly rearrangement")

    14.times do |night|
      event = mechanic.operation.run!(MIDNIGHT + night.days)
      next if event.nil?

      by_name = story.locations.to_h { |location| [ location.name, location.reload.exits.pluck(:name) ] }
      event.summary.scan(/(.+?) now opens onto (.+?) instead of (.+?)\./).each do |mover, now, before|
        mover = mover.strip
        assert_includes by_name.fetch(mover), now,
                        "night #{night} says #{mover} opens onto #{now}, and it does not"
        assert_not_includes by_name.fetch(mover), before,
                            "night #{night} says #{mover} no longer opens onto #{before}, and it still does"
      end
    end
  end

  test "a world with nothing mobile does not move" do
    @story.locations.update_all(mobile: false)
    before = exits_by_name

    assert_nil @mechanic.operation.run!(MIDNIGHT)
    assert_equal before, exits_by_name
  end

  private

  def place(name, mobile: false)
    create(:location, story: @story, name: name, mobile: mobile)
  end

  def connect(from, to, distance:)
    [ [ from, to ], [ to, from ] ].each do |origin, destination|
      create(:location_connection, location: origin, connected_location: destination,
                                   distance: distance, travel_method: "walking")
    end
  end

  # Back to the graph setup declares, so a second run starts where the first did.
  def reset!
    LocationConnection.where(location: @story.locations).delete_all
    @story.world_events.destroy_all
    @movers.each { |mover| connect(@hub, mover, distance: "adjacent") }
    @movers.zip(@anchors).each { |mover, anchor| connect(mover, anchor, distance: "across the district") }
  end

  # The mobile places whose fixed landmark is not the one they started with.
  def changed_anchors
    @movers.zip(@anchors).to_h.filter_map do |mover, anchor|
      now = mover.reload.exits.where(mobile: false).first
      [ mover, now ] unless now == anchor
    end.to_h
  end

  def exit_counts
    @story.locations.order(:id).to_h { |location| [ location.name, location.reload.exits.count ] }
  end

  def exits_by_name
    @story.locations.order(:id).to_h { |location| [ location.name, location.reload.exits.pluck(:name).sort ] }
  end

  def reachable_from(start)
    reached = Set.new([ start.id ])
    frontier = [ start ]
    while (location = frontier.pop)
      location.exits.each { |exit| frontier << exit if reached.add?(exit.id) }
    end
    reached
  end
end
