require "test_helper"

class Story::MapTest < ActiveSupport::TestCase
  # A READER, and the rule rather than the habit -- `Playthrough::Debug`'s rule,
  # pinned the way that class pins it: nothing on this page may write a row,
  # ask a model anything or move the world's clock.
  test "drawing the map writes nothing" do
    story = walked_story
    before = table_counts

    map = Story::Map.new(story)
    map.nodes
    map.edges
    map.interiors
    map.dead_ends

    assert_equal before, table_counts
  end

  # THE COLUMN IS HOPS OUT, which is the one thing to read off the picture
  # before anything else -- and it is counted from where the party is standing
  # when there is a party.
  test "a column is one hop out from where the party is standing" do
    story = walked_story
    here = story.locations.find_by(name: "The Hall")
    playthrough = create(:playthrough, story: story, current_location: here)

    map = Story::Map.new(story, playthrough: playthrough)

    assert_equal here, map.standing
    assert_equal 0, map.node_for(here).column
    assert_equal 1, map.node_for(story.locations.find_by(name: "The Stair")).column
    assert_equal 2, map.node_for(story.locations.find_by(name: "The Cellar")).column
    assert map.node_for(here).here
  end

  # NOBODY IS STANDING ANYWHERE IN A WORLD NOBODY IS PLAYING. The walk still
  # needs somewhere to start, so it starts where a game would.
  test "a story with no playthrough has a root and nobody standing on it" do
    story = walked_story

    map = Story::Map.new(story)

    assert_nil map.standing
    assert_equal story.opening_location, map.root
    assert_empty map.nodes.select(&:here)
  end

  # THE SAME WORLD DRAWS THE SAME PICTURE, which is what makes it safe to store
  # no layout and throw no die. Two maps built over the same records must agree
  # on every coordinate.
  test "the layout is the same every time it is computed" do
    story = walked_story

    first = Story::Map.new(story).nodes.map { |node| [ node.name, node.column, node.row, node.cx, node.cy ] }
    second = Story::Map.new(story).nodes.map { |node| [ node.name, node.column, node.row, node.cx, node.cy ] }

    assert_equal first, second
  end

  # ONE LINE PER DOORWAY, NOT PER ROW. The table holds two rows for a door (the
  # ruling of 2026-09-03) and the picture draws one line, with the other row
  # kept so the page can say the two disagree.
  test "the two rows of one doorway collapse onto one edge" do
    story = walked_story
    edges = Story::Map.new(story).edges

    assert_equal 2, edges.size
    assert edges.none?(&:one_sided?)
    assert edges.none?(&:directions_disagree?)
  end

  # A DOOR WRITTEN IN ONE DIRECTION ONLY is an asymmetry in the records and not
  # a one-way exit -- `LocationConnection`'s header says why those stay
  # unsupported -- so the map reports it rather than drawing it as ordinary.
  test "a doorway the table holds one row of is reported" do
    story = walked_story
    hall = story.locations.find_by(name: "The Hall")
    attic = create(:location, story: story, name: "The Attic")
    create(:location_connection, location: hall, connected_location: attic)

    map = Story::Map.new(story)

    assert_equal [ "The Attic" ], map.one_sided_edges.map { |edge| edge.to.name }
  end

  # A HAZARD IS WRITTEN ON ONE ROW AND IS THEREFORE ONE-WAY BY CONSTRUCTION
  # (`LocationConnection`'s header). One line collapses two rows, so the line has
  # to name the direction the toll is on -- the drop down hurts and the climb
  # back out does not, and a picture that said only "hazard: drop" would have
  # dropped the mechanic.
  test "a hazard is reported in the direction its row is written in" do
    story = create(:story)
    hall = create(:location, story: story, name: "The Hall")
    cellar = create(:location, story: story, name: "The Cellar")
    ledge = create(:location, story: story, name: "The Ledge")
    create(:location_connection, :hazardous, location: hall, connected_location: cellar)
    create(:location_connection, location: cellar, connected_location: hall)
    create(:location_connection, location: cellar, connected_location: ledge)
    create(:location_connection, :hazardous, location: ledge, connected_location: cellar)

    readings = Story::Map.new(story).hazardous_edges
                                    .to_h { |edge| [ [ edge.from.name, edge.to.name ], edge.hazard_readings ] }

    assert_equal [ "hazard: drop going The Hall -> The Cellar" ], readings.fetch([ "The Hall", "The Cellar" ])
    assert_equal [ "hazard: drop going The Ledge -> The Cellar" ], readings.fetch([ "The Cellar", "The Ledge" ])
  end

  # THE PEOPLE COUNTED ARE THE LAYER THE MAP IS ABOUT, the way the things beside
  # them already are. A corpse keeps its `location_id`, so a playthrough that has
  # emptied a room must not be shown somebody still standing in it --
  # `Playthrough#cast_in`'s reason, one table over.
  test "somebody this game has killed is not counted as standing anywhere" do
    story = walked_story
    hall = story.locations.find_by(name: "The Hall")
    playthrough = create(:playthrough, story: story, current_location: hall)
    create(:character, story: story, location: hall)
    slain = create(:character, story: story, location: hall)
    create(:playthrough_vitals, :dead, playthrough: playthrough, character: slain)

    assert_equal 2, Story::Map.new(story).node_for(hall).people
    assert_equal 1, Story::Map.new(story, playthrough: playthrough).node_for(hall).people
  end

  # EVERY PLACE STILL GETS DRAWN when nothing leads to it, and a piece of the
  # graph is laid out in a band under the piece before it -- so two components
  # can never land on top of each other.
  test "a place nothing leads to is drawn on its own, in its own band" do
    story = walked_story
    orphan = create(:location, story: story, name: "The Island")

    map = Story::Map.new(story)
    node = map.node_for(orphan)

    assert_equal 0, node.column
    assert map.nodes.select { |other| other.column.zero? }.map(&:row).uniq.size > 1,
           "the orphan must not share a cell with the root"
    assert_equal [ "The Island" ], map.dead_ends.map(&:name)
  end

  # A STUB IS ON THE FRONTIER BY CONSTRUCTION -- walking into one is what
  # realizes it -- and the edge that reaches it is an exit nobody has taken.
  test "an unvisited place and the edge that reaches it are the frontier" do
    story = walked_story
    map = Story::Map.new(story)

    assert_equal [ "The Cellar" ], map.nodes.select(&:frontier?).map(&:name)
    assert_equal [ [ "The Stair", "The Cellar" ] ],
                 map.frontier_edges.map { |edge| [ edge.from.name, edge.to.name ] }
  end

  # WHAT IS ON THE FLOOR IS READ FROM THE LAYER THE MAP IS ABOUT: one game's own
  # copies when there is a playthrough, the world's templates when there is not.
  # `Item`'s header owns the split.
  test "the things counted are the layer the map is about" do
    story = walked_story
    hall = story.locations.find_by(name: "The Hall")
    playthrough = create(:playthrough, story: story, current_location: hall)
    create(:item, :lying, location: hall, name: "a brass key")
    create(:item, character: nil, playthrough: playthrough, location: hall, name: "the party's lamp")

    assert_equal 1, Story::Map.new(story).node_for(hall).things
    assert_equal 1, Story::Map.new(story, playthrough: playthrough).node_for(hall).things
  end

  # --- the insides ----------------------------------------------------------

  # THE CHECKED-IN FIXTURE, which is the only world in the repository with an
  # interior, so the plan is measured against geometry a seed file can actually
  # write.
  test "a place with rooms inside it is drawn to scale, on its storey" do
    story = WorldSeed::Loader.new(interior_document).load!

    interior = Story::Map.new(story).interiors.sole
    storey = interior.storeys.sole

    assert_equal "The Rusted Anchor", interior.name
    assert_equal [ 12, 8 ], interior.footprint
    assert_equal 0, storey.z
    assert_equal [ "The Back Room", "The Taproom" ], storey.rooms.map(&:name).sort

    taproom = storey.rooms.find { |room| room.name == "The Taproom" }
    assert_equal [ 0, 0 ], [ taproom.x, taproom.y ]
    assert_equal [ 7 * Story::Map::PACE, 8 * Story::Map::PACE ], [ taproom.width, taproom.height ]
  end

  # THE DOOR GOES ON THE WALL THEY SHARE. The intervals are half-open
  # (`Location::Box`), so the taproom's far edge and the back room's near edge
  # are the same line at x = 7 -- which is why two rooms sharing a wall do not
  # overlap and a door is expressible at all.
  test "a door is drawn at the middle of the wall two connected rooms share" do
    story = WorldSeed::Loader.new(interior_document).load!

    door = Story::Map.new(story).interiors.sole.storeys.sole.doorways.sole
    pace = Story::Map::PACE

    assert_equal 7 * pace, door.x1
    assert_equal 7 * pace, door.x2
    assert_equal Story::Map::DOOR_PACES * pace, door.y2 - door.y1
    assert_equal 4 * pace, (door.y1 + door.y2) / 2, "the middle of the eight paces they share"
  end

  # A ROOM MAY SIT LEFT OF OR ABOVE ITS PARENT'S OWN ORIGIN -- `Location` puts no
  # floor under `x` and `y` -- and the plan is then drawn shifted. The door has to
  # be shifted with it: a wall drawn at one origin and a door drawn at another is
  # exactly the out-of-footprint fault this page exists to make visible, drawn as
  # though nothing were wrong.
  test "a door on a plan shifted off zero lands on the wall it belongs to" do
    story = create(:story)
    place = create(:location, story: story, name: "The Keep")
    west = placed_room(story, place, name: "The West Wing", x: -3)
    east = placed_room(story, place, name: "The East Wing", x: 0, width: 4)
    connect(west, east)

    storey = Story::Map.new(story).interiors.sole.storeys.sole
    door = storey.doorways.sole
    wall = storey.rooms.find { |room| room.name == "The East Wing" }.x

    assert_equal 3 * Story::Map::PACE, wall, "the west wing is drawn from the plan's own origin"
    assert_equal [ wall, wall ], [ door.x1, door.x2 ]
  end

  # TWO ROOMS THE TABLE CONNECTS THAT DO NOT TOUCH get no door, because there is
  # no wall to put one in. The edge is still on the graph, which is where that
  # fault shows up.
  test "connected rooms that do not touch get no door" do
    story = create(:story)
    place = create(:location, :with_a_footprint, story: story, name: "The Keep")
    near = placed_room(story, place, name: "The Near Room", x: 0)
    far = placed_room(story, place, name: "The Far Room", x: 9)
    connect(near, far)

    assert_empty Story::Map.new(story).interiors.sole.storeys.sole.doorways
  end

  # A STAIR IS AN EDGE AND NOT A SHAPE -- the captain's third ruling of
  # 2026-09-06 -- so it is read off the connection's `travel_method` and drawn
  # once on each of the two storeys it joins, in the room it leaves from.
  test "a stair between storeys is marked on both plans" do
    story = create(:story)
    place = create(:location, :with_a_footprint, story: story, name: "The Keep")
    ground = placed_room(story, place, name: "The Ground Floor", x: 0, z: 0)
    upper = placed_room(story, place, name: "The Upper Floor", x: 0, z: 1)
    connect(ground, upper, :indoor_connection)

    storeys = Story::Map.new(story).interiors.sole.storeys

    assert_equal [ 1, 0 ], storeys.map(&:z), "highest first, the way a building is read"
    assert_equal [ false ], storeys.first.stairs.map(&:up)
    assert_equal [ true ], storeys.last.stairs.map(&:up)
    assert_match "The Upper Floor", storeys.last.stairs.sole.reading
  end

  # A CELLAR IS DRAWN UNDER THE GROUND FLOOR, which is what "highest first" means
  # once a storey index can be negative. `#build_interior` sorts on `-z` and
  # nothing about that had to change -- but nothing in the app could WRITE a
  # negative storey until `Location::Interior::BASEMENTS` existed, so the order
  # had never been asserted below zero. The plan is the page a reader checks a
  # building against, and a cellar drawn above the hall would be a picture that
  # contradicts its own records.
  test "a storey below the ground is drawn under it, and the stair into it points down" do
    story = create(:story)
    place = create(:location, :with_a_footprint, story: story, name: "The Keep")
    cellar = placed_room(story, place, name: "The Cellar", x: 0, z: -1)
    ground = placed_room(story, place, name: "The Ground Floor", x: 0, z: 0)
    upper = placed_room(story, place, name: "The Upper Floor", x: 0, z: 1)
    connect(ground, cellar, :indoor_connection)
    connect(ground, upper, :indoor_connection)

    storeys = Story::Map.new(story).interiors.sole.storeys

    assert_equal [ 1, 0, -1 ], storeys.map(&:z), "highest first, and the cellar is the lowest of the three"
    # The ground floor leaves by two stairs: one up to the roof and one down to
    # the cellar. Both are marked in the room they leave FROM, so the arrows are
    # what tell a reader which is which.
    assert_equal [ false, true ], storeys[1].stairs.map(&:up).sort_by(&:to_s)
    assert_equal [ true ], storeys.last.stairs.map(&:up), "out of the cellar is upward"
    assert_match "storey -1", storeys[1].stairs.find { |stair| !stair.up }.reading
  end

  # A STAIR OUT OF THE BUILDING IS NOT A STOREY OF IT. A child's `z` is read in
  # ITS OWN parent's frame (`Location::Box`), so a stairs connection to a room
  # under a different parent says nothing about which floor of this one it
  # reaches -- it is on the graph above and nowhere on this plan.
  test "a stair to a room under another parent is left off both plans" do
    story = create(:story)
    keep = create(:location, :with_a_footprint, story: story, name: "The Keep")
    tower = create(:location, :with_a_footprint, story: story, name: "The Tower")
    ground = placed_room(story, keep, name: "The Ground Floor", x: 0, z: 0)
    top = placed_room(story, tower, name: "The Tower Top", x: 0, z: 1)
    connect(ground, top, :indoor_connection)

    storeys = Story::Map.new(story).interiors.flat_map(&:storeys)

    assert_equal 2, storeys.size, "one storey drawn in each building"
    assert_empty storeys.flat_map(&:stairs)
  end

  # A PLACE HOLDING PLACED ROOMS WITH NO FOOTPRINT OF ITS OWN is a fault
  # `rake game:doctor` reports, and the map draws it rather than dropping it --
  # a fault nobody can see is the thing this page exists to stop.
  test "a place with rooms and no footprint is still drawn" do
    story = create(:story)
    place = create(:location, story: story, name: "The Keep")
    placed_room(story, place, name: "The Ground Floor", x: 0)

    interior = Story::Map.new(story).interiors.sole

    assert_nil interior.footprint
    assert_not interior.footprint?
    assert_equal 1, interior.storeys.sole.rooms.size
  end

  private

  # A world of three places in a line, two of them walked into and the third a
  # stub nobody has reached. `last_protagonist_visit` is the only record of a
  # crossing there is, and it is a column on the WORLD rather than on a game.
  def walked_story
    story = create(:story)
    hall = create(:location, story: story, name: "The Hall", last_protagonist_visit: story.start_time)
    stair = create(:location, story: story, name: "The Stair", last_protagonist_visit: story.start_time)
    cellar = create(:location, :stub, story: story, name: "The Cellar")
    connect(hall, stair)
    connect(stair, cellar)
    story
  end

  # Both rows of one doorway, which is what every writer in the app makes.
  def connect(a, b, *traits)
    create(:location_connection, *traits, location: a, connected_location: b)
    create(:location_connection, *traits, location: b, connected_location: a)
  end

  # A room placed on a storey of a parent that has a plane to read it in. Fixed
  # numbers and never rolled -- a factory that threw dice for a box would land
  # an overlap on whoever ran the suite next.
  def placed_room(story, parent, name:, x:, z: 0, width: 3)
    create(:location, story: story, name: name, parent_location: parent,
                      x: x, y: 0, z: z, width: width, depth: 8)
  end

  def interior_document
    WorldSeed.parse(File.read(Rails.root.join("test/fixtures/files/a-world-with-an-interior.yml")))
  end

  def table_counts
    ActiveRecord::Base.connection.tables.sort.to_h do |table|
      [ table, ActiveRecord::Base.connection.select_all("SELECT COUNT(*) AS c FROM #{table}").first["c"] ]
    end
  end
end
