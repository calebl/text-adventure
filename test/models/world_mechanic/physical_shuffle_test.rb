require "test_helper"

class WorldMechanic::PhysicalShuffleTest < ActiveSupport::TestCase
  setup do
    @story = create(:story, start_time: Time.utc(2026, 8, 31, 23))
    @hub = create(:location, story: @story, name: "Moving Hub", mobile: true)
    @movers = 3.times.map { |n| create(:location, story: @story, name: "Moving Room #{n}", mobile: true) }
    @anchors = 3.times.map { |n| create(:location, story: @story, name: "Fixed Room #{n}") }
    @movers.each { |room| connect(@hub, room) }
    @keys = @movers.each_with_index.map do |room, n|
      create(:item, character: nil, location: @hub, name: "Door key #{n}", use_kind: "key")
    end
    @doors = @movers.zip(@anchors, @keys).map do |room, anchor, key|
      connect(room, anchor, barrier: "keyed", key_template: key).first
    end
    @first = create(:playthrough, story: @story, current_location: @hub)
    @second = create(:playthrough, story: @story, current_location: @hub)
    @doors.zip(@keys).each do |door, key|
      Playthrough::Passage.open!(@first, door, means: "key", item: @first.items.find_by!(template: key))
    end
    Playthrough::Passage.open!(@second, @doors.first, means: "lockpick")
    @doors.each_with_index do |door, index|
      create(:playthrough_toll, playthrough: @first, location_connection: door,
                               location: door.connected_location, hazard: "drop", sequence: -index - 1)
    end
    @mechanic = create(:world_mechanic, story: @story)
  end

  test "moving a keyed doorway preserves both games' openings and each directed hazard" do
    @doors.first.update!(hazard: "drop", hazard_die: 4)
    originals = @doors.to_h { |door| [ door.location_id, receipts(door) ] }
    passage_rows = Playthrough::Passage.where(playthrough: [ @first, @second ]).order(:id).map(&:attributes)
    toll_rows = @first.tolls.order(:id).map(&:attributes)

    event = @mechanic.operation.run!(Time.utc(2026, 9, 1))

    assert event
    assert_equal 6, @first.passages.count
    assert_equal 2, @second.passages.count
    moved = 0
    @movers.zip(@anchors, @keys).each_with_index do |(room, original, key), index|
      forward = LocationConnection.find_by!(location: room, connected_location: @anchors)
      reverse = LocationConnection.find_by!(location: forward.connected_location, connected_location: room)
      assert_equal @doors[index].id, forward.id
      moved += 1 if forward.connected_location != original
      [ forward, reverse ].each do |edge|
        assert_equal "keyed", edge.barrier
        assert_equal key, edge.key_template
        assert edge.open_for?(@first)
        assert_equal index.zero?, edge.open_for?(@second)
        assert_equal originals.fetch(room.id), receipts(edge)
      end
      index.zero? ? assert_equal("drop", forward.hazard) : assert_nil(forward.hazard)
      assert_nil reverse.hazard
    end
    assert_operator moved, :>=, 2
    assert_equal passage_rows, Playthrough::Passage.where(playthrough: [ @first, @second ]).order(:id).map(&:attributes)
    @first.tolls.order(:id).zip(toll_rows).each do |toll, before|
      assert_equal before.except("location_connection_id"), toll.attributes.except("location_connection_id")
      original_door = @doors.find { |edge| edge.id == before.fetch("location_connection_id") }
      if original_door.reload.connected_location_id != toll.location_id
        assert_nil toll.location_connection_id
        assert_equal toll.location.name, toll.where_it_was
      else
        assert_equal original_door.id, toll.location_connection_id
      end
    end
  end

  test "a failed doorway rewrite rolls back deleted barriers and opening receipts" do
    edges = LocationConnection.where(location: @story.locations).order(:id).map(&:attributes)
    passages = Playthrough::Passage.where(playthrough: [ @first, @second ]).order(:id).map(&:attributes)
    tolls = @first.tolls.order(:id).map(&:attributes)
    writer = LocationConnection.method(:create!)
    calls = 0
    failing = lambda do |**attributes|
      calls += 1
      raise ActiveRecord::StatementInvalid, "injected write failure" if calls == 2

      writer.call(**attributes)
    end

    LocationConnection.stub(:create!, failing) do
      assert_raises(ActiveRecord::StatementInvalid) { @mechanic.operation.run!(Time.utc(2026, 9, 1)) }
    end

    assert_equal edges, LocationConnection.where(location: @story.locations).order(:id).map(&:attributes)
    assert_equal passages, Playthrough::Passage.where(playthrough: [ @first, @second ]).order(:id).map(&:attributes)
    assert_equal tolls, @first.tolls.order(:id).map(&:attributes)
    assert_equal 2, calls
    assert_empty @story.world_events
  end

  private

  def connect(from, to, **attributes)
    [ [ from, to ], [ to, from ] ].map do |origin, destination|
      create(:location_connection, location: origin, connected_location: destination, **attributes)
    end
  end

  def receipts(edge)
    edge.passages.order(:playthrough_id).map do |row|
      row.attributes.slice("playthrough_id", "means", "opened_at", "opened_by_item_id")
    end
  end
end
