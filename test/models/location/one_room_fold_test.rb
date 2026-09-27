require "test_helper"

class Location::OneRoomFoldTest < ActiveSupport::TestCase
  # THE SHAPE A WORLD GENERATED BEFORE THE FIX CARRIES: a chamber born with a
  # 5 x 3 footprint, laid out by `Location::Interior` itself as the one room
  # that fills it, the doorway moved onto that room, and a game played there.
  def setup
    @story = create(:story)
    @protagonist = create(:character, story: @story, fullname: "Kael Veyra", is_protagonist: true)
    @shaft = create(:location, story: @story, name: "Gravity Core Maintenance Shaft")
    @place = create(:location, story: @story, name: "Core Access Chamber", width: 5, depth: 3,
                               description: "A building-sized description nobody read.")
    Location::Interior.lay_out!(@place, parameters: Location::Parameters.from("storeys_above" => "ground floor only"))
    @room = @place.child_locations.sole
    @room.update!(detail_level: :realized, description: "Frost on the rails and a hum in the floor.",
                  lore: "The core was sealed after the second breach.",
                  last_protagonist_visit: Time.utc(2026, 9, 20, 12))
    @out = create(:location_connection, location: @shaft, connected_location: @room,
                                        distance: "adjacent", travel_method: "climbing")
    @back = create(:location_connection, location: @room, connected_location: @shaft,
                                         distance: "adjacent", travel_method: "climbing")
    @playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @room)
  end

  def fold = Location::OneRoomFold.candidates(@story).sole

  test "the package's shape is a proven candidate" do
    assert_equal "Core Access Chamber room 1", @room.name
    assert_equal [ @place, @room ], [ fold.place, fold.room ]
    assert_predicate fold, :proven?, fold.reasons.join("; ")
  end

  test "folding keeps the place row, by the name the player chose, and makes it a room" do
    fold.fold!

    @place.reload
    assert_not Location.exists?(@room.id), "the placeholder room is gone"
    assert_equal "Core Access Chamber", @place.name
    assert_nil @place.width
    assert_nil @place.depth
    assert_not_predicate @place, :place?
    assert_empty @place.child_locations
    assert_equal "Frost on the rails and a hum in the floor.", @place.description, "the prose the player read"
    assert_equal "The core was sealed after the second breach.", @place.lore
    assert_equal Time.utc(2026, 9, 20, 12), @place.last_protagonist_visit
  end

  test "folding moves every piece of the game played in the room onto the place" do
    scene = create(:scene, story: @story, location: @room)
    thing = create(:item, :lying, location: @room, name: "frayed cable tie")
    engineer = create(:character, story: @story, fullname: "Mira Solis", location: @room)
    npc = create(:playthrough_npc_state, playthrough: @playthrough, character: engineer, location: @room)
    blow = create(:playthrough_blow, playthrough: @playthrough, location: @room)
    toll = create(:playthrough_toll, playthrough: @playthrough, location: @room)
    volition = create(:playthrough_volition, playthrough: @playthrough, location: @room)
    drift = create(:playthrough_drift, playthrough: @playthrough, location: @room)
    step = create(:quest_step, :reach_location, quest: create(:quest, story: @story), target_name: @room.name,
                                                target: @room)
    event = create(:world_event, world_mechanic: create(:world_mechanic, story: @story))
    event.locations << @room

    fold.fold!

    [ scene, thing, engineer, npc, blow, toll, volition, drift ].each do |row|
      assert_equal @place.id, row.reload.location_id, "#{row.class.name} ##{row.id} was left behind"
    end
    assert_equal @place, @playthrough.reload.current_location
    assert_equal @place, step.reload.target
    assert_equal [ @place ], event.reload.locations.to_a
  end

  test "folding keeps the doorway, both ways, with its labels" do
    fold.fold!

    assert_equal [ @shaft.id, @place.id ], [ @out.reload.location_id, @out.connected_location_id ]
    assert_equal [ @place.id, @shaft.id ], [ @back.reload.location_id, @back.connected_location_id ]
    assert_equal %w[adjacent climbing], [ @out.distance, @out.travel_method ]
    assert_includes @shaft.reload.exits, @place
    assert_includes @place.reload.exits, @shaft
  end

  test "a thing's corner in the room is cleared, because the room it keeps has no box" do
    thing = create(:item, :lying, location: @room, x: 1, y: 1)

    fold.fold!

    assert_equal [ @place.id, nil, nil ], [ thing.reload.location_id, thing.x, thing.y ]
  end

  test "the folded world is healthy to the doctor and a second pass finds nothing" do
    fold.fold!

    assert_empty Location::OneRoomFold.candidates(@story)
    assert_empty Story::Doctor.new(@story).findings.map(&:code) &
                 %i[one_room_place_left_split connection_terminating_on_a_place place_with_a_footprint_and_no_rooms]
  end

  # --- what is only diagnosed ---------------------------------------------

  test "a doorway onto the place itself is not the shape, and the doctor says so" do
    create(:location_connection, location: @place, connected_location: @shaft)

    assert_not_predicate fold, :proven?
    assert_match(/a doorway lands on Core Access Chamber itself/, fold.reasons.join)
    assert_raises(Location::OneRoomFold::NotProven) { fold.fold! }
    assert Location.exists?(@room.id)

    finding = Story::Doctor.new(@story).findings.find { |row| row.code == :one_room_place_left_split }
    assert_equal [ :warning, :manual, @place ], [ finding.severity, finding.remedy, finding.subject ]
  end

  test "history in the place itself, a room that does not fill it, or a room never written is not the shape" do
    create(:scene, story: @story, location: @place)
    assert_match(/play history of its own/, fold.reasons.join)
    Scene.where(location: @place).delete_all

    @room.update!(width: 4)
    assert_match(/does not fill the whole/, fold.reasons.join)
    @room.update!(width: 5, detail_level: :stub)
    assert_match(/never written out/, fold.reasons.join)
  end

  test "a single room with a name of its own is somebody's floor plan, not a candidate" do
    @room.update!(name: "The Frost Gallery")

    assert_empty Location::OneRoomFold.candidates(@story)
  end

  test "a place of several rooms is never a candidate" do
    tavern = create(:location, story: @story, name: "The Tin Cup", width: 12, depth: 8)
    Location::Interior.lay_out!(tavern)

    assert_operator tavern.child_locations.count, :>, 1
    assert_equal [ @place ], Location::OneRoomFold.candidates(@story).map(&:place)
  end

  # A COLUMN THAT NAMES A LOCATION AND IS NOT MOVED would leave a row pointing
  # at the room the fold deletes, so the schema's own foreign keys are the list.
  test "every foreign key onto locations is one the fold moves" do
    moved = Location::OneRoomFold::REFERENCES.map { |model, column| [ model.table_name, column.to_s ] }
    handled_elsewhere = [ %w[locations parent_location_id], %w[locations_world_events location_id] ]

    ActiveRecord::Base.connection.tables.each do |table|
      ActiveRecord::Base.connection.foreign_keys(table).select { |key| key.to_table == "locations" }.each do |key|
        pair = [ table, key.column ]
        assert_includes moved + handled_elsewhere, pair, "#{table}.#{key.column} names a location and is not folded"
      end
    end
  end
end
