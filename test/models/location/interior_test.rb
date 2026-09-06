require "test_helper"

# WHAT A LAID-OUT INTERIOR HAS TO BE TRUE OF, and most of it is asserted over
# MANY SEEDS rather than over one. A layout is rolled, so a single example
# proves that one building came out right and says nothing about the next one;
# the guarantees `Location::Interior` claims -- no two rooms in the same place,
# every room reachable, every door in both directions, nobody over the exit cap
# -- are claims about EVERY building it can roll. `#every_interior` is the loop
# that holds it to them.
#
# THE PROPERTY LOOP IS NOT A LOTTERY. Each place is laid out from its own id, so
# the worlds it walks are the same worlds on every run and a failure lands on
# whoever broke it rather than on whoever ran the suite next -- which is the rule
# `test/factories/location_connections.rb` states in full.
class Location::InteriorTest < ActiveSupport::TestCase
  # A range of footprints wide enough to reach every branch of the grid: one
  # too small to divide at all, one that fits a single row, and several that
  # fill out `ROOMS_PER_STOREY`.
  FOOTPRINTS = [ [ 4, 4 ], [ 9, 4 ], [ 8, 8 ], [ 12, 8 ], [ 18, 6 ], [ 15, 11 ], [ 18, 14 ] ].freeze

  # HOW MANY PLACES THE PROPERTY LOOP LAYS OUT. Enough that the rolls differ --
  # every place has its own id, so every one is a different building -- and few
  # enough that the loop stays a test rather than a benchmark.
  PLACES = 24

  def setup
    @story = create(:story)
  end

  def place_with(width: 12, depth: 8, name: "The Rusted Anchor")
    create(:location, :stub, story: @story, name: name, width: width, depth: depth)
  end

  def laid_out(**attributes)
    place = place_with(**attributes)
    Location::Interior.lay_out!(place)
    place.reload
  end

  def rooms_of(place) = place.child_locations.order(:id).to_a

  # Every interior this suite reasons about: a spread of footprints, each laid
  # out several times over under different ids.
  def every_interior
    PLACES.times.map do |number|
      width, depth = FOOTPRINTS[number % FOOTPRINTS.size]
      laid_out(width: width, depth: depth, name: "Place #{number}")
    end
  end

  # --- what it writes -------------------------------------------------------

  test "a place gets rooms of its own, and they are stubs with boxes" do
    place = laid_out

    rooms = rooms_of(place)
    assert_predicate rooms.size, :positive?
    assert(rooms.all? { |room| room.parent_location_id == place.id })
    assert(rooms.all?(&:stub?))
    assert(rooms.all?(&:placed?))
    assert(rooms.none?(&:description))
    assert(rooms.none?(&:lore))
  end

  # A ROOM IS BORN THE WAY EVERY OTHER ROOM IS, which is what going through
  # `Location::Generator.create_stub!` buys: a danger the engine rolled, and no
  # second place in the app that knows what a new room is.
  test "an interior's rooms carry a rolled danger like any other new room" do
    rooms = rooms_of(laid_out)

    assert(rooms.all? { |room| Location::Danger::ROLLED.include?(room.danger) })
  end

  test "a room is named after the place it is inside and numbered" do
    place = laid_out

    assert_equal Location::Interior.placeholder_name(place, 1), rooms_of(place).first.name
    assert(rooms_of(place).map(&:name).uniq.size == rooms_of(place).size)
  end

  # The teaser is what slice 3 hands the model that eventually writes this room,
  # so it carries what the ENGINE knows and nothing it does not.
  test "a room's teaser states its size and its storey and invents nothing" do
    room = rooms_of(laid_out).first

    assert_includes room.teaser, "#{room.width} by #{room.depth} paces"
    assert_includes room.teaser, "storey #{room.z}"
  end

  test "the place keeps the footprint the world gave it" do
    place = laid_out(width: 18, depth: 14)

    assert_equal [ 18, 14 ], [ place.width, place.depth ]
  end

  # A place nobody sized is sized here rather than refused -- see the header on
  # `Location::Interior`.
  test "a place with no footprint is given one" do
    place = create(:location, :stub, story: @story)
    Location::Interior.lay_out!(place)

    assert_predicate place.reload, :interior?
    assert_includes Location::Interior::FOOTPRINT_SIDES, place.width
    assert_includes Location::Interior::FOOTPRINT_SIDES, place.depth
    assert_predicate rooms_of(place).size, :positive?
  end

  # --- laid out once, ever --------------------------------------------------

  test "laying a place out twice leaves the building it already had" do
    place = laid_out

    before = rooms_of(place).map(&:id)
    assert_no_difference [ "Location.count", "LocationConnection.count" ] do
      Location::Interior.lay_out!(place)
    end
    assert_equal before, rooms_of(place).map(&:id)
  end

  test "an unsaved place cannot be laid out inside" do
    place = build(:location, :stub, story: @story, width: 12, depth: 8)

    assert_raises(ArgumentError) { Location::Interior.lay_out!(place) }
  end

  # --- determinism ----------------------------------------------------------
  #
  # The whole reason the layout is drawn from `Roll` rather than from `rand`:
  # the same place lays out the same way in any process for ever, so `DRY_RUN=1`
  # and an offline sweep re-derive what the real run wrote.

  # THE SAME PLACE, LAID OUT AGAIN FROM NOTHING. The rooms are taken away and
  # the same row is handed back to the generator -- which is what a second
  # process, a `DRY_RUN=1` rehearsal and an offline sweep all are: the same
  # story id and the same place id, with no memory of the first answer.
  test "the same place lays out the same way twice" do
    place = laid_out
    first = layout_of(place)

    place.child_locations.destroy_all
    Location::Interior.lay_out!(place.reload)

    assert_equal first, layout_of(place.reload)
  end

  test "two places of one story are two different buildings" do
    one = layout_of(laid_out(name: "The Rusted Anchor"))
    other = layout_of(laid_out(name: "The Bell House"))

    assert_not_equal one, other
  end

  # Every number and every door of one interior, as something two runs can be
  # compared on. Names carry the place's own name, so they are dropped: what is
  # being compared is the SHAPE.
  def layout_of(place)
    rooms = rooms_of(place)
    numbers = rooms.map { |room| room.box.to_s }
    doors = LocationConnection.where(location: rooms).order(:location_id, :connected_location_id)
                              .map { |row| [ rooms.index { |r| r.id == row.location_id },
                                             rooms.index { |r| r.id == row.connected_location_id },
                                             row.travel_method, row.distance ] }

    [ place.width, place.depth, numbers, doors ]
  end

  # --- the geometry, over many seeds ----------------------------------------

  test "no two rooms of one place are ever in the same place at once" do
    every_interior.each do |place|
      rooms_of(place).combination(2).each do |one, other|
        assert_not one.overlaps?(other), "#{one.name} (#{one.box}) overlaps #{other.name} (#{other.box})"
      end
    end
  end

  test "every room is inside the footprint it is read in" do
    every_interior.each do |place|
      rooms_of(place).each do |room|
        assert room.box.inside_footprint?(place.width, place.depth),
               "#{room.name} is #{room.box} in a #{place.width}x#{place.depth} place"
      end
    end
  end

  # The rooms tile the footprint exactly: no gaps and no overlaps, which is
  # `Location::Interior`'s stated decision about corridors.
  test "the rooms of a storey cover the whole footprint" do
    every_interior.each do |place|
      rooms_of(place).group_by(&:z).each_value do |storey|
        covered = storey.sum { |room| room.width * room.depth }
        assert_equal place.width * place.depth, covered, "storey of #{place.name} does not tile its footprint"
      end
    end
  end

  test "a storey holds no more rooms than the range allows" do
    every_interior.each do |place|
      storeys = rooms_of(place).group_by(&:z)

      assert_includes Location::Interior::STOREYS, storeys.size
      storeys.each_value do |storey|
        assert_operator storey.size, :<=, Location::Interior::ROOMS_PER_STOREY.max
      end
    end
  end

  # --- the doors ------------------------------------------------------------

  test "every door is written in both directions" do
    every_interior.each do |place|
      rooms = rooms_of(place)
      LocationConnection.where(location: rooms).each do |row|
        assert LocationConnection.exists?(location: row.connected_location, connected_location: row.location),
               "#{row.location.name} -> #{row.connected_location.name} has no way back"
      end
    end
  end

  test "no room leads more ways out than the cap on a room" do
    every_interior.each do |place|
      rooms_of(place).each do |room|
        assert_operator room.exits.count, :<=, Location::ExitsSchema::MAX_EXITS, "#{room.name} is over the cap"
      end
    end
  end

  # The slot the way IN to a place will need one day -- see
  # `Location::Interior`'s header.
  test "the entry room keeps a way out spare" do
    every_interior.each do |place|
      entry = Location::Interior.entry_room(place)

      assert_operator entry.exits.count, :<, Location::ExitsSchema::MAX_EXITS
    end
  end

  test "a door only ever joins two rooms that share a wall or two floors" do
    every_interior.each do |place|
      each_door(place) do |one, other, row|
        if row.travel_method == Location::Interior::STAIRS
          assert_equal 1, (one.z - other.z).abs, "#{one.name} and #{other.name} are not one floor apart"
        else
          assert one.box.shares_a_wall?(other.box), "#{one.name} and #{other.name} share no wall"
        end
      end
    end
  end

  # THE THIRD RULING, ASSERTED: floors are kept aligned, so a stairwell arrives
  # where it set off from.
  test "every stair joins two rooms that stand over each other" do
    every_interior.each do |place|
      each_door(place) do |one, other, row|
        next unless row.travel_method == Location::Interior::STAIRS

        assert one.box.shares_ground?(other.box), "the stairs from #{one.name} to #{other.name} do not line up"
      end
    end
  end

  test "every storey is reachable from the entry room" do
    every_interior.each do |place|
      rooms = rooms_of(place)
      assert_equal rooms.map(&:id).sort, reachable(rooms).map(&:id).sort,
                   "#{place.name} has rooms nothing can walk to"
    end
  end

  # THE DOCTOR OVER EVERY BUILDING THIS FILE CAN ROLL. `Story::Doctor#geometry`
  # is the other half of the same rules -- it reports the layouts a database
  # carries, this one writes them -- so a generator that could produce a finding
  # would be a generator arguing with the tool that grades it.
  test "no interior the generator lays out is a finding" do
    every_interior

    assert_empty Story::Doctor.new(@story).findings.map(&:code) & GEOMETRY_CODES
  end

  GEOMETRY_CODES = %i[location_with_a_partial_box location_with_an_impossible_extent
                      location_with_a_box_and_no_parent location_with_a_box_outside_a_footprint
                      overlapping_sibling_locations locations_containing_each_other
                      location_outside_its_parents_footprint interior_with_an_unreachable_room
                      stairs_between_rooms_that_do_not_line_up
                      place_with_a_footprint_and_no_rooms
                      door_between_rooms_that_share_no_wall].freeze

  # --- the two travel-time rules --------------------------------------------

  test "an interior door's distance comes from the geometry" do
    every_interior.each do |place|
      each_door(place) do |one, other, row|
        assert_equal Location::Interior.new(place).send(:distance_for, one.box.paces_to(other.box)), row.distance
      end
    end
  end

  test "a stair is taken by taking stairs" do
    place = every_interior.find { |candidate| rooms_of(candidate).map(&:z).uniq.size > 1 }
    refute_nil place, "no interior in the property loop had a second storey"

    stairs = LocationConnection.where(location: rooms_of(place), travel_method: Location::Interior::STAIRS)
    assert_predicate stairs.count, :positive?
    assert_includes LocationConnection::TRAVEL_METHODS.keys, Location::Interior::STAIRS
  end

  # AN EXTERIOR EDGE KEEPS ITS LABEL, which is the other half of the rule: there
  # is no geometry out there to derive one from.
  test "the edges a place already had are left exactly as they were" do
    place = place_with
    road = create(:location, story: @story, name: "The Harbour Road")
    outside = create(:location_connection, location: place, connected_location: road,
                                           distance: "a long journey", travel_method: "riding")

    Location::Interior.lay_out!(place)

    assert_equal [ "a long journey", "riding" ], outside.reload.slice(:distance, :travel_method).values
  end

  # --- the closure ----------------------------------------------------------
  #
  # It finds nothing to do on a layout this file built, which is the point of
  # the construction. It is exercised directly on an interior somebody else
  # broke, because a guarantee about the ROWS has to hold whatever put them
  # there.

  test "a stranded room is joined back on to what is reachable" do
    place = laid_out(width: 12, depth: 8)
    rooms = rooms_of(place)
    stranded = rooms.last
    LocationConnection.where(location: stranded).or(LocationConnection.where(connected_location: stranded)).destroy_all

    assert_not_includes reachable(rooms).map(&:id), stranded.id
    Location::Interior.new(place).send(:close_connectivity!, rooms)

    assert_includes reachable(rooms_of(place)).map(&:id), stranded.id
  end

  # --- the seam -------------------------------------------------------------

  test "a place is a row carrying a footprint, and a room is not" do
    place = place_with

    assert_predicate place, :place?
    Location::Interior.lay_out!(place)
    assert(rooms_of(place).none?(&:place?))
  end

  test "a stub with no footprint is not a place, so nothing generated changes" do
    assert_not create(:location, :stub, story: @story).place?
  end

  private

  def each_door(place)
    rooms = rooms_of(place).index_by(&:id)

    LocationConnection.where(location: rooms.keys).order(:id).each do |row|
      one = rooms[row.location_id]
      other = rooms[row.connected_location_id]
      next if other.nil?

      yield one, other, row
    end
  end

  # The rooms that can be walked to from the first one, through the interior's
  # own doors -- the sweep this test does not get to borrow from the generator,
  # so that a broken generator cannot agree with itself.
  def reachable(rooms)
    by_id = rooms.index_by(&:id)
    seen = [ rooms.first ].compact

    seen.each do |room|
      LocationConnection.from_location(room).pluck(:connected_location_id).each do |id|
        neighbour = by_id[id]
        seen << neighbour if neighbour && !seen.include?(neighbour)
      end
    end

    seen
  end
end
