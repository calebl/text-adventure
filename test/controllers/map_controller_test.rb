require "test_helper"

class MapControllerTest < ActionDispatch::IntegrationTest
  # THE PICTURE RENDERS FOR A WORLD SOMEBODY IS PLAYING, and every mark on it is
  # asserted by something only that mark can produce -- so a node, an edge, the
  # frontier or a floor plan silently ceasing to draw fails here.
  test "show draws the graph, the frontier and the party for a playthrough" do
    playthrough = walked_world

    get playthrough_map_path(playthrough)

    assert_response :success

    # The graph itself, with one node per place and one line per DOORWAY rather
    # than per row -- the table holds two rows for the walked door and one for
    # the unwalked one, and three places make two lines.
    assert_select "svg.map-graph"
    assert_select "svg.map-graph .nodes .place", 3
    assert_select "svg.map-graph .edges line", 2

    # Where the party is standing, and the stub nobody has walked into.
    assert_select "svg.map-graph rect.node.here", 1
    assert_select "svg.map-graph rect.node.stub", 1

    # THE FRONTIER, which is the whole reason the page exists: the edge out to
    # the stub is dashed on the picture and named in the list under it.
    assert_select "svg.map-graph line.edge.frontier", 1
    assert_select "h2", text: "the frontier — exits nobody has taken"
    assert_select "table td", text: "The Sunken Stair"

    # The counts, off the records rather than off the drawing.
    assert_match "3 places", response.body
    assert_match "2 doorways", response.body
  end

  # THE SAME WORLD WITH NOBODY IN IT. A story has a map before anybody plays
  # it -- that is what there is to look at after `rake game:new` -- so the
  # second route takes a story and draws no party.
  test "show draws a story with no playthrough and no party on it" do
    playthrough = walked_world
    story = playthrough.story

    get story_map_path(story)

    assert_response :success
    assert_select "svg.map-graph .nodes .place", 3
    assert_select "svg.map-graph rect.node.here", 0
    assert_match "nobody is playing this one", response.body
  end

  # THE CHECKED-IN INTERIOR, loaded from the one file in the repository that has
  # one, so the floor plan is asserted against the geometry a seed file can
  # actually write rather than against numbers this test invented.
  test "show draws the floor plan of a world with an interior" do
    story = WorldSeed::Loader.new(interior_document).load!

    get story_map_path(story)

    assert_response :success

    # The plane the rooms are read in, and the two rooms on it.
    assert_select "svg.map-plan", 1
    assert_select "svg.map-plan rect.footprint", 1
    assert_select "svg.map-plan rect.room", 2

    # TO SCALE. The taproom is seven paces across and eight deep, at the plan's
    # own origin; the back room begins where it ends.
    pace = Story::Map::PACE
    assert_select "svg.map-plan rect.room[x=?][y=?][width=?][height=?]",
                  "0", "0", (7 * pace).to_s, (8 * pace).to_s
    assert_select "svg.map-plan rect.room[x=?]", (7 * pace).to_s

    # THE DOOR ON THE WALL THEY SHARE, drawn at x = 7 paces because the
    # intervals are half-open and that is where one room ends and the other
    # begins.
    assert_select "svg.map-plan line.door", 1
    assert_select "svg.map-plan line.door[x1=?][x2=?]", (7 * pace).to_s, (7 * pace).to_s

    # The place that contains them is on the graph as well, with its rooms
    # counted, and the road outside is not inside anything.
    assert_match "The Rusted Anchor", response.body
    assert_match "The Harbour Road", response.body
    assert_match "storey 0", response.body
  end

  # A STAIR IS AN EDGE (the captain's third ruling of 2026-09-06), so it is
  # drawn as a mark inside the room it leaves from, once on each of the two
  # storeys it joins -- and the arrow is drawn as the CHARACTER. It rendered as
  # the literal source of an HTML entity until somebody looked at the page in a
  # browser, which is the sort of fault only a rendered assertion catches.
  test "show draws a stair on both of the storeys it joins" do
    story = create(:story)
    keep = create(:location, :with_a_footprint, story: story, name: "The Keep")
    ground = create(:location, story: story, name: "The Ground Floor", parent_location: keep,
                               x: 0, y: 0, z: 0, width: 6, depth: 8)
    upper = create(:location, story: story, name: "The Upper Floor", parent_location: keep,
                              x: 0, y: 0, z: 1, width: 6, depth: 8)
    create(:location_connection, :indoor_connection, location: ground, connected_location: upper)
    create(:location_connection, :indoor_connection, location: upper, connected_location: ground)

    get story_map_path(story)

    assert_response :success
    assert_select "svg.map-plan", 2
    assert_select "svg.map-plan text.stair", 2
    assert_select "svg.map-plan text.stair", text: /↑/
    assert_select "svg.map-plan text.stair", text: /↓/
    assert_no_match "&amp;uarr;", response.body
    assert_match "storey 1", response.body
  end

  # THE GATE IS ON THE ENDPOINT and not only on the link that reaches it, which
  # is `DebugController`'s rule for its reason: this app has no auth, so a page
  # standing behind a hidden link is a page anybody with the link can read.
  test "show is not found when the debug view is off" do
    playthrough = walked_world

    Playthrough::Debug.stub(:enabled?, false) do
      get playthrough_map_path(playthrough)
      assert_response :not_found

      get story_map_path(playthrough.story)
      assert_response :not_found
    end
  end

  private

  # A world with three places: where the party stands, a room they walked in
  # from, and a stub nothing has been walked into. The two visited places carry
  # a `last_protagonist_visit`, which is the only record of a crossing there is.
  def walked_world
    playthrough = create(:playthrough, :started)
    story = playthrough.story
    here = playthrough.current_location
    here.update!(last_protagonist_visit: story.start_time)

    behind = create(:location, story: story, name: "The Lamp Room",
                               last_protagonist_visit: story.start_time)
    create(:location_connection, location: here, connected_location: behind)
    create(:location_connection, location: behind, connected_location: here)

    stair = create(:location, :stub, story: story, name: "The Sunken Stair")
    create(:location_connection, location: here, connected_location: stair)
    create(:location_connection, location: stair, connected_location: here)

    playthrough
  end

  # The one world in the repository with an interior. It is a fixture rather
  # than a seeded world by the captain's fourth ruling of 2026-09-06, which
  # leaves the three checked-in worlds flat.
  def interior_document
    WorldSeed.parse(File.read(Rails.root.join("test/fixtures/files/a-world-with-an-interior.yml")))
  end
end
