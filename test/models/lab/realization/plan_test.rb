require "test_helper"

# WHAT THE DRAWING IS ALLOWED TO SAY ABOUT A STORED ROW: exactly what the row
# says, and nothing where the row says nothing.
class Lab::Realization::PlanTest < ActiveSupport::TestCase
  # THE ONE ASSERTION THE SLICE EXISTS FOR. Every rectangle is the stored `x`,
  # `y`, `width` and `depth` at `Story::Map::PACE` pixels to the pace -- if this
  # drifts, the picture and the table beside it are describing two buildings.
  test "every rectangle is the stored position and extent at the map's own scale" do
    plan = plan_for(:a_building_with_a_plan)
    ground = plan.storeys.find { |storey| storey.z.zero? }
    stored = rooms_of(:a_building_with_a_plan).select { |room| room["storey"].zero? }

    assert_equal stored.size, ground.rooms.size
    ground.rooms.zip(stored).each do |drawn, row|
      assert_equal row["x"] * Story::Map::PACE, drawn.x, "#{row["name"]} is drawn at the wrong x"
      assert_equal row["y"] * Story::Map::PACE, drawn.y, "#{row["name"]} is drawn at the wrong y"
      assert_equal row["width"] * Story::Map::PACE, drawn.width
      assert_equal row["depth"] * Story::Map::PACE, drawn.height
      assert_equal row["name"], drawn.name
    end
  end

  # A SET STORED BEFORE THE POSITIONS IS NOT DRAWN AT ALL, which is
  # `Eval::Realization::Scorer::Reading#records_the_way_back?`'s rule: an absent
  # key is a different state from a recorded nothing, and a plan guessed from an
  # extent with no position would be a picture of a building nobody generated.
  test "a building stored before x and y is not drawable" do
    assert_nil plan_for(:a_building)
    assert_not Lab::Realization::Plan.positioned?(rooms_of(:a_building).first)
  end

  # THE GATE IS THE KEY AND NOT THE VALUE. A room against the west wall has an
  # `x` of zero, and a plan that read zero as missing would refuse to draw the
  # commonest room in every building.
  test "a position of zero is a position" do
    room = rooms_of(:a_building_with_a_plan).first

    assert_equal 0, room["x"]
    assert Lab::Realization::Plan.positioned?(room)
    assert_not_nil plan_for(:a_building_with_a_plan)
  end

  test "a sample with no rooms at all has no plan" do
    assert_nil plan_for(:a_building_that_picked_nothing)
  end

  # ONE PANEL PER STOREY, HIGHEST FIRST -- the order a building is read in and
  # not the order the integers come in (`Story::Map::Interior`).
  test "the storeys come back highest first" do
    assert_equal [ 0, -1 ], plan_for(:a_building_with_a_plan).storeys.map(&:z)
  end

  # ADJACENCY IS NOT A DOOR. The four ground-floor rooms share four walls
  # between them; the layout opened three of those in a serpentine, and the
  # drawing must show three. Deriving doors from the boxes would draw a building
  # `Location::Interior` refused to build.
  test "a door is drawn only where the layout opened one" do
    ground = plan_for(:a_building_with_a_plan).storeys.find { |storey| storey.z.zero? }
    readings = ground.doorways.map(&:reading)

    assert_equal 3, ground.doorways.size
    assert_includes readings, "The Loading Floor <-> The Salt Store"
    assert_includes readings, "The Salt Store <-> The Wet Dock"
    assert_includes readings, "The Counting Room <-> The Wet Dock"
    assert_not_includes readings, "The Loading Floor <-> The Wet Dock",
                        "they share a wall and the layout left it shut"
  end

  # AND TWO ROOMS THE TABLE JOINS THAT MEET AT A CORNER GET NO DOOR, which is
  # `Story::Map`'s own rule drawn from `Location::Box::MINIMUM_DOORWAY`: a
  # doorway is a person wide, so there is nowhere to put one. It is a fault
  # worth seeing rather than a line drawn through a corner.
  test "two rooms joined in the table that meet only at a corner get no door" do
    sample = build(:lab_realization_sample, :a_building_with_a_plan)
    rooms = sample.row["after"]["rooms"]
    rooms[0]["doors_to"] = [ 1, 3 ]
    rooms[3]["doors_to"] = [ 0, 1, 2 ]

    ground = Lab::Realization::Plan.for(sample.reading, name: "x").storeys.find { |one| one.z.zero? }
    assert_equal 3, ground.doorways.size,
                 "the diagonal pair shares no wall, so the count does not move"
  end

  # A DOOR IS TWO ROWS AND ONE MARK. `doors_to` names it on both rooms, so a
  # drawing that took both would put two lines in one gap.
  test "a door between two rooms is drawn once" do
    ground = plan_for(:a_building_with_a_plan).storeys.find { |storey| storey.z.zero? }

    assert_equal ground.doorways.map(&:reading), ground.doorways.map(&:reading).uniq
  end

  # A STAIR IS A MARK ON EACH OF THE TWO STOREYS IT JOINS, pointing the way the
  # far room's storey says -- the captain's third ruling of 2026-09-06 drawn.
  test "a stair is marked on both storeys and points the right way" do
    storeys = plan_for(:a_building_with_a_plan).storeys.index_by(&:z)

    assert_equal [ false ], storeys[0].stairs.map(&:up)
    assert_equal [ true ], storeys[-1].stairs.map(&:up)
    assert_includes storeys[0].stairs.first.reading, "The Cellar Stair"
  end

  # DANGER AND HAZARD ARE READ THROUGH `Location`'S OWN TABLES, so a room the
  # drawing calls dangerous is one `Location#dangerous?` would call dangerous.
  test "danger and hazard are read the way a Location reads them" do
    rooms = plan_for(:a_building_with_a_plan).storeys.index_by(&:z)[0].rooms.index_by(&:name)

    assert_not rooms["The Loading Floor"].dangerous?
    assert rooms["The Salt Store"].dangerous?
    assert rooms["The Wet Dock"].hazardous?
    assert_not rooms["The Salt Store"].hazardous?, "a hazard needs a key AND a die"
  end

  # A HAZARD WITH NO DIE IS NOT A HAZARD (`Location#hazardous?`), and a plan that
  # marked one would be marking a toll nothing pays.
  test "a hazard with no die is not marked" do
    sample = build(:lab_realization_sample, :a_building_with_a_plan)
    sample.row["after"]["rooms"].each { |room| room["hazard_die"] = nil }

    drawn = Lab::Realization::Plan.for(sample.reading, name: "x").storeys.flat_map(&:rooms)
    assert drawn.none?(&:hazardous?)
  end

  # EVERY ROOM OF A BUILDING IS A STUB UNTIL SOMEBODY WALKS IN, and nobody is
  # ever standing in a lab draw -- there is no playthrough at all.
  test "every room reads as a stub and nobody is standing in one" do
    drawn = plan_for(:a_building_with_a_plan).storeys.flat_map(&:rooms)

    assert drawn.all?(&:stub?)
    assert drawn.none?(&:here?)
  end

  # THE FOOTPRINT IS THE ROOMS' OWN UNION, which is a reading and not a guess:
  # they tile it exactly (`Location::Interior`). Reported as a footprint rather
  # than as nil because the partial reads a missing one as a fault
  # `rake game:doctor` would report, and here there is no fault to report.
  test "the footprint is the rooms' own union" do
    plan = plan_for(:a_building_with_a_plan)

    assert plan.footprint?
    assert_equal [ 4, 4 ], plan.footprint
    assert_equal 4, plan.plan_width
    assert_equal 4, plan.plan_height
    assert_equal 0, plan.origin_x
    assert_equal 0, plan.origin_y
  end

  # AND THE TOOLTIP SAYS WHAT THE COLOUR CANNOT. A stroke says that a room costs
  # something to be in; only the reading says which of the two it is.
  test "a room's tooltip names its danger and its hazard" do
    rooms = plan_for(:a_building_with_a_plan).storeys.index_by(&:z)[0].rooms.index_by(&:name)

    assert_match "dangerous", rooms["The Salt Store"].reading
    assert_match "hazardous", rooms["The Wet Dock"].reading
    assert_no_match(/dangerous|hazardous/, rooms["The Loading Floor"].reading)
    assert_match "The Loading Floor", rooms["The Loading Floor"].reading
  end

  private

  def plan_for(trait)
    Lab::Realization::Plan.for(build(:lab_realization_sample, trait).reading,
                               name: "The Fishmonger's Warehouse")
  end

  def rooms_of(trait) = build(:lab_realization_sample, trait).reading.rooms
end
