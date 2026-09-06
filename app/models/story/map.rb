# THE WORLD GRAPH, DRAWN. Every place a story has named, every doorway between
# two of them, and -- where a place has an inside -- its rooms laid out to scale
# on the storey they stand on.
#
# WHY IT EXISTS: *"coordinates come before pictures"*. Slice 1 gave a place a
# footprint and a room a box (`Location::Box`), and the moment there are numbers
# there has to be something that shows them, because the fault this programme
# keeps hitting is not a wrong number -- it is a SHAPE nobody looked at. The
# scout's example is the one to keep in mind: The Iron Gate Descends dead-ends,
# and a picture of its graph would have shown that at a glance as *every
# unexplored edge leading up and out*. So the frontier is marked here as loudly
# as anything on the page, and the counts beside it are the answer to "how much
# of this world can still be walked into".
#
# A READER AND NOTHING ELSE, and that is the rule rather than the habit --
# `Playthrough::Debug`'s rule, for its reason. Nothing here asks a model
# anything, writes a row, calls `Story#catch_up_world!` or advances a
# playthrough: looking at a world must not move it. `test/models/story/map_test.rb`
# pins that with a table-wide before/after snapshot.
#
# NO LAYOUT IS STORED, AND NO DIE IS THROWN. Where a node lands is a function of
# the records alone -- a breadth-first walk out from where the party is standing,
# in id order at every step -- so the same world draws the same picture in any
# process, after any restart, for ever, and it needs neither a column to keep it
# in nor a seed from `Roll` to reproduce it. That is the whole reason the layout
# is layered rather than force-directed: a spring layout would need iteration
# counts, a stored seed and a tolerance, and would still move a node when a
# stub was born three rooms away.
#
# WHAT THE COLUMNS MEAN, and it is the one thing to read off the picture before
# anything else: a column is HOPS FROM WHERE YOU ARE STANDING. So the frontier
# of a world is its right-hand edge, an exit nobody has taken is a dashed line,
# and a world that has run out of anywhere to go has nothing past the column the
# party is in. A story with no playthrough is walked from `Story#opening_location`
# instead, which is where a game would start.
#
# PLACES NOTHING LEADS TO STILL GET DRAWN. A world graph is not always one piece:
# a place that contains rooms (the captain's second ruling of 2026-09-06) has no
# doorway of its own, and a badly seeded world can leave a room hanging. Each
# component is walked from its own lowest-numbered place and laid out in a BAND
# below the one before it, so two components can never be drawn on top of each
# other and a place standing on its own is visibly standing on its own.
#
# WHAT "FRONTIER" MEANS HERE, said out loud because the records cannot say more:
# `locations.last_protagonist_visit` is a column on the WORLD, not on a game, so
# an unvisited place is one NOBODY has walked into in any playthrough of this
# story. Every stub is one by construction -- walking into a stub is what
# realizes it. An edge is on the frontier when either end is unvisited, which is
# the honest reading of "an exit not yet taken" from records that never recorded
# a crossing.
#
# THE GEOMETRY IS `Location::Box`'s, AND IS NOT RE-DERIVED. Every position and
# extent on this page comes off a box; what this class adds is the pixels, which
# is drawing rather than geometry. The one piece of arithmetic that is neither
# is WHERE A DOOR GOES on a wall two rooms share -- `#doorway_between`.
#
#   REJECTED: putting `#shared_wall` on `Location::Box`, beside `#overlaps?`,
#   which is where the family belongs and where the box header already
#   anticipates a door. It is not there because this slice adds a READER and no
#   engine code, and a value object gains a method when something in the engine
#   needs it. Slice 2's layout generator has to place a door to open one; that
#   is the moment the arithmetic moves onto `Box` and this class calls it
#   instead of owning it. Until then it is here, once, and the view has none.
#
# WHY IT IS NOT ON THE PLAY PAGE. The reading experience is a stage of its own
# (`ta-api-iface`) and this is an instrument, not a scene: it is reached the way
# `DebugController` is reached, behind `Playthrough::Debug.enabled?`, and it is
# as dense as it likes because nothing a player reads shares a stylesheet with
# it.
class Story::Map
  # --- how big the picture is, in pixels ------------------------------------
  #
  # Named here rather than in the view because the view emits markup and does no
  # arithmetic: every coordinate on the page is computed in this file, so a node
  # and the edge that reaches it cannot disagree about where it is.

  # One node's box. Wide enough for a place name at the debug page's font --
  # thirty-odd characters, which is what it takes to tell "Grenn's Boarding
  # House hallway" from "Grenn's Boarding House, Room 3" -- and tall enough for
  # the marks line under it.
  NODE_WIDTH = 216
  NODE_HEIGHT = 46

  # The grid a node lands on. A column is one hop out; a row is one node within
  # that hop. Both are larger than the node itself, which is what leaves the
  # gutters an edge is drawn through.
  COLUMN_STEP = 280
  ROW_STEP = 74

  # The blank border around everything, so a node on the outside edge is not cut
  # in half by the viewBox.
  MARGIN = 24

  # HOW BIG A PACE IS DRAWN. `Location::Box`'s unit is the pace and the engine
  # owns what it means in metres (`Location::Box::METRES_PER_PACE`); this is the
  # only place it becomes a number of pixels.
  PACE = 22

  # A DOOR'S WIDTH ON A SHARED WALL, in paces, and it is drawn at the middle of
  # whatever the two rooms actually share. A door is not a modelled thing -- the
  # record is a `LocationConnection`, which says two rooms are walkable and says
  # nothing about where the gap in the wall is -- so this is the picture
  # admitting it draws the connection at the centre of the wall because it has
  # nowhere better to put it.
  DOOR_PACES = 2

  # ONE PLACE ON THE GRAPH, and everything the picture says about it.
  #
  # `column` and `row` are the grid; `cx` and `cy` are the middle of the node in
  # the drawing. Both are here because the grid is what a test asserts and the
  # pixels are what the view emits.
  Node = Data.define(:location, :column, :row, :cx, :cy, :people, :things, :rooms, :here, :visited) do
    def name = location.name
    def stub? = location.stub?
    def realized? = !location.stub?
    def dangerous? = location.dangerous?
    def hazardous? = location.hazardous?
    def interior? = location.interior?
    def box = location.box

    # NOT WALKED INTO BY ANYBODY, which is what puts it on the frontier. See the
    # class header for why this is a fact about the world rather than about one
    # game.
    def frontier? = !visited

    def x = cx - (NODE_WIDTH / 2.0)
    def y = cy - (NODE_HEIGHT / 2.0)
  end

  # ONE DOORWAY, as one line rather than as the two rows the table holds.
  #
  # `back` is the row for the other direction, and it is nil when the table
  # holds only one of the pair. That is an ASYMMETRY IN THE RECORDS and not a
  # one-way exit: one-way exits are unsupported and deliberately deferred
  # (`LocationConnection`'s header), so a single row is something to look at.
  Edge = Data.define(:from, :to, :out, :back, :frontier) do
    def one_sided? = back.nil?
    def frontier? = frontier
    def hazardous? = out.hazardous? || back&.hazardous? || false
    def stairs? = out.travel_method == "taking stairs"

    # The two rows disagreeing about how far it is or how you get there. Written
    # in both directions from one answer, so they should never differ.
    def directions_disagree?
      return false if back.nil?

      out.distance != back.distance || out.travel_method != back.travel_method
    end

    def x1 = from.cx
    def y1 = from.cy
    def x2 = to.cx
    def y2 = to.cy
    def mid_x = (x1 + x2) / 2.0
    def mid_y = (y1 + y2) / 2.0

    # What a reader gets on hover, without a line of JavaScript: SVG draws a
    # `<title>` as a tooltip on its own.
    def reading
      parts = [ "#{from.name} <-> #{to.name}", out.distance.to_s, out.travel_method.to_s, out.time_to_travel.to_s ]
      parts << "hazard: #{out.hazard || back&.hazard}" if hazardous?
      parts << "only one row in the table" if one_sided?
      parts << "the two rows disagree" if directions_disagree?
      parts << "nobody has walked this" if frontier?
      parts.reject(&:blank?).join(" - ")
    end
  end

  # ONE ROOM ON A FLOOR PLAN: its node, its box, and the rectangle it is drawn
  # as. The rectangle is `PACE` pixels to the pace, so a plan is to scale and two
  # rooms that share a wall are drawn sharing it.
  Room = Data.define(:node, :box, :x, :y, :width, :height) do
    def name = node.name
  end

  # WHERE THE GAP IN A SHARED WALL IS DRAWN. A segment, in pixels, plus the two
  # rooms it joins -- see `#doorway_between` and the header's rejected
  # alternative for why the arithmetic is in this file.
  Doorway = Data.define(:x1, :y1, :x2, :y2, :reading)

  # A STAIR, WHICH IS AN EDGE AND NOT A SHAPE. The captain's third ruling of
  # 2026-09-06: each floor is its own plane and a stair is a
  # `LocationConnection` with `travel_method: "taking stairs"`. So it is drawn
  # as a mark inside the room it leaves from, on the storey it leaves from, and
  # it appears once on each of the two storeys it joins.
  Stair = Data.define(:x, :y, :up, :reading)

  # ONE PLANE OF A PLACE THAT HAS AN INSIDE. `z` is a storey index and not a
  # height -- 2.5D, so there is nothing vertical to draw.
  Storey = Data.define(:z, :rooms, :doorways, :stairs)

  # A PLACE WITH AN INSIDE, and its storeys, highest first -- which is the order
  # a building is read in and not the order the integers come in.
  #
  # `plan_width` and `plan_height` are the drawing's viewport: the parent's own
  # footprint where it has one, widened to hold any room that sticks out of it.
  # A room outside its parent's footprint is a fault `rake game:doctor` reports
  # (`location_with_a_box_and_no_parent` is its neighbour); this page draws it
  # rather than cropping it, because a fault nobody can see is the thing this
  # page exists to stop.
  Interior = Data.define(:place, :footprint, :origin_x, :origin_y, :plan_width, :plan_height, :storeys) do
    def name = place.name
    def footprint? = !footprint.nil?
  end

  # `playthrough` is optional: a story has a map whether or not anybody is
  # playing it, and without one there is nowhere the party is standing.
  def initialize(story, playthrough: nil)
    @story = story
    @playthrough = playthrough
  end

  attr_reader :story, :playthrough

  # WHERE THE PARTY IS STANDING, or NIL when nobody is playing this world. A
  # story has a map before anybody plays it, and a picture that claimed somebody
  # was standing in the opening room would be inventing a game.
  def standing = playthrough&.current_location

  # WHERE THE WALK STARTS, and so which place is column zero: the party's room,
  # or -- with no party -- the room a game would open in, which is where the
  # hops would be counted from the moment anybody pressed start.
  def root
    @root ||= standing || story.opening_location
  end

  def nodes = layout.fetch(:nodes)

  def node_for(location) = nodes_by_id[location&.id]

  # EVERY DOORWAY, ONCE. The table holds two rows per door (the ruling of
  # 2026-09-03) and this collapses them onto the unordered pair, keeping the
  # lower-numbered end's row as `out` so the same door reads the same way every
  # time it is drawn.
  def edges
    @edges ||= connections.group_by { |row| [ row.location_id, row.connected_location_id ].minmax }
                          .filter_map { |(low, high), rows| build_edge(low, high, rows) }
  end

  # THE PICTURE'S SIZE. Read straight into the `viewBox`, so the drawing scales
  # to whatever width the page gives it and never has a coordinate outside it.
  def width = layout.fetch(:width)
  def height = layout.fetch(:height)

  # --- what the counts under the picture say --------------------------------

  def frontier_edges = edges.select(&:frontier?)
  def stub_count = nodes.count(&:stub?)
  def realized_count = nodes.count(&:realized?)
  def unvisited_count = nodes.count(&:frontier?)
  def hazardous_edges = edges.select(&:hazardous?)
  def one_sided_edges = edges.select(&:one_sided?)

  # PLACES WITH NOTHING LEADING OUT OF THEM. The dead end, named as a number: a
  # place the player can be standing in with no exit is the fault this page was
  # asked for, and a place that contains rooms is not one -- nobody stands in a
  # container.
  def dead_ends
    nodes.reject { |node| node.rooms.positive? }
         .select { |node| edges.none? { |edge| edge.from == node || edge.to == node } }
  end

  # --- the insides ----------------------------------------------------------

  # EVERY PLACE THAT HAS AN INSIDE, in id order.
  #
  # THE QUESTION IS NOT `Location#interior?`, and that is worth saying because it
  # reads as though it should be: a PLACED ROOM carries an extent as well as a
  # position, so `#interior?` is true of every room in every building and asking
  # it here would draw a plan of each one. What earns a plan is HOLDING A ROOM
  # THAT HAS BEEN PLACED -- or, for a place whose inside is declared and still
  # empty, carrying an extent and no position, which is `Location::Box`'s
  # `:footprint` shape and is exactly the shape a room does not have.
  def interiors
    @interiors ||= locations.select { |place| plan_worthy?(place) }
                            .map { |place| build_interior(place) }
  end

  def plan_worthy?(place)
    children_of(place).any?(&:placed?) || Location::Box.shape(place) == :footprint
  end

  def interiors? = interiors.any?

  private

  # Every place in the story, loaded once, in id order. Everything else on this
  # page is a walk over this array rather than a query, so the picture is one
  # round trip and a node's neighbours are the same objects as the nodes.
  def locations
    @locations ||= story.locations.order(:id).to_a
  end

  def locations_by_id = @locations_by_id ||= locations.index_by(&:id)

  def nodes_by_id = @nodes_by_id ||= nodes.index_by { |node| node.location.id }

  def children_of(place)
    @children ||= locations.group_by(&:parent_location_id)
    @children.fetch(place.id, [])
  end

  # Both rows of every door in this story, ordered so that grouping them is
  # stable.
  def connections
    @connections ||= LocationConnection.where(location_id: locations.map(&:id))
                                       .order(:location_id, :connected_location_id).to_a
  end

  # WHO THE RECORD SAYS IS STANDING IN EACH ROOM -- `characters.location_id`,
  # which is `Character.present_in`'s set counted in one query rather than one
  # per node. The PARTY is not in it and cannot be: the protagonist and any
  # companion are wherever the PLAYTHROUGH is, which is the "you are here" mark
  # instead.
  def people_by_location
    @people_by_location ||= story.characters.where.not(location_id: nil).group(:location_id).count
  end

  # WHAT IS LYING ON EACH FLOOR, from whichever of the two item layers this map
  # is about: one game's own copies when there is a playthrough, the world's
  # templates when there is not (`Item`'s header for the split).
  def things_by_location
    @things_by_location ||= begin
      scope = playthrough ? Item.of_playthrough(playthrough) : Item.templates
      scope.where(location_id: locations.map(&:id)).where(character_id: nil).group(:location_id).count
    end
  end

  # --- the layout -----------------------------------------------------------

  # THE WHOLE PICTURE, COMPUTED ONCE. A breadth-first walk out from `here`, then
  # one from the lowest-numbered place in each piece of the graph that walk did
  # not reach, each piece laid out in a band under the one before it.
  def layout
    @layout ||= begin
      placed = {}
      row_offset = 0

      walk_order.each do |start|
        next if placed.key?(start.id)

        hops = hops_from(start, placed)
        by_column = hops.group_by { |_id, column| column }
                        .transform_values { |pairs| pairs.map(&:first) }

        by_column.each do |column, ids|
          ids.each_with_index { |id, index| placed[id] = [ column, row_offset + index ] }
        end

        row_offset += by_column.values.map(&:size).max.to_i + 1
      end

      build_layout(placed)
    end
  end

  # THE ORDER PIECES OF THE GRAPH ARE WALKED IN: where the party is standing
  # first, then everywhere else in id order. Deterministic, which is the whole
  # point -- see the header.
  def walk_order
    ([ root ] + locations).compact.uniq
  end

  # HOW MANY HOPS EACH PLACE IN THIS PIECE OF THE GRAPH IS FROM ITS ROOT, in
  # discovery order -- so a place is laid out beside the place that leads to it
  # rather than beside whatever happens to share its id range. Neighbours are
  # queued in id order at every step, which is what makes the walk repeatable.
  def hops_from(root, already_placed)
    seen = { root.id => 0 }
    queue = [ root.id ]

    until queue.empty?
      id = queue.shift
      neighbours_of(id).each do |neighbour|
        next if seen.key?(neighbour) || already_placed.key?(neighbour)

        seen[neighbour] = seen[id] + 1
        queue << neighbour
      end
    end

    seen
  end

  # BOTH ENDS OF EVERY ROW THAT TOUCHES THIS PLACE, in id order. Undirected on
  # purpose: a door is two rows and the picture draws one line, so the walk must
  # cross a door the table only half recorded.
  def neighbours_of(id)
    @adjacency ||= connections.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |row, index|
      index[row.location_id] << row.connected_location_id
      index[row.connected_location_id] << row.location_id
    end

    @adjacency[id].uniq.sort
  end

  def build_layout(placed)
    columns = placed.values.map(&:first).max.to_i
    rows = placed.values.map(&:last).max.to_i

    nodes = locations.filter_map do |location|
      column, row = placed[location.id]
      next if column.nil?

      build_node(location, column, row)
    end

    {
      nodes: nodes,
      width: (2 * MARGIN) + (columns * COLUMN_STEP) + NODE_WIDTH,
      height: (2 * MARGIN) + (rows * ROW_STEP) + NODE_HEIGHT
    }
  end

  def build_node(location, column, row)
    Node.new(
      location: location,
      column: column,
      row: row,
      cx: MARGIN + (column * COLUMN_STEP) + (NODE_WIDTH / 2.0),
      cy: MARGIN + (row * ROW_STEP) + (NODE_HEIGHT / 2.0),
      people: people_by_location.fetch(location.id, 0),
      things: things_by_location.fetch(location.id, 0),
      rooms: children_of(location).count,
      here: !standing.nil? && location == standing,
      visited: !location.last_protagonist_visit.nil?
    )
  end

  def build_edge(low, high, rows)
    from = nodes_by_id[low]
    to = nodes_by_id[high]
    return nil if from.nil? || to.nil?

    out = rows.find { |row| row.location_id == low } || rows.first
    back = rows.find { |row| row.location_id == high && row != out }

    Edge.new(from: from, to: to, out: out, back: back,
             frontier: from.frontier? || to.frontier?)
  end

  # --- the floor plans ------------------------------------------------------

  def build_interior(place)
    rooms = children_of(place).select(&:placed?)
    footprint = place.interior? ? [ place.width, place.depth ] : nil
    origin_x, origin_y, plan_width, plan_height = plan_bounds(footprint, rooms)

    storeys = rooms.group_by { |room| room.box.z }.sort_by { |z, _| -z }.map do |z, on_this_storey|
      build_storey(z, on_this_storey, origin_x, origin_y)
    end

    Interior.new(place: place, footprint: footprint,
                 origin_x: origin_x, origin_y: origin_y,
                 plan_width: plan_width, plan_height: plan_height,
                 storeys: storeys)
  end

  # THE VIEWPORT ONE PLANE IS DRAWN IN, in paces: the parent's footprint at its
  # own origin, widened to hold any room outside it. Every storey of one place
  # gets the SAME viewport, which is ruling 3 as a drawing rule -- floors are
  # kept aligned, so a stairwell at (x, y) on one storey is at (x, y) on the
  # next, and two plans of one building must be readable one against the other.
  def plan_bounds(footprint, rooms)
    boxes = rooms.map(&:box)
    min_x = ([ 0 ] + boxes.map(&:x)).min
    min_y = ([ 0 ] + boxes.map(&:y)).min
    max_x = ([ footprint&.first.to_i ] + boxes.map { |box| box.x + box.width }).max
    max_y = ([ footprint&.last.to_i ] + boxes.map { |box| box.y + box.depth }).max

    [ min_x, min_y, [ max_x - min_x, 1 ].max, [ max_y - min_y, 1 ].max ]
  end

  def build_storey(z, rooms, origin_x, origin_y)
    drawn = rooms.map { |room| build_room(room, origin_x, origin_y) }

    Storey.new(z: z, rooms: drawn,
               doorways: doorways_among(drawn),
               stairs: stairs_from(drawn))
  end

  def build_room(room, origin_x, origin_y)
    box = room.box

    Room.new(node: node_for(room), box: box,
             x: (box.x - origin_x) * PACE, y: (box.y - origin_y) * PACE,
             width: box.width * PACE, height: box.depth * PACE)
  end

  # EVERY DOOR ON THIS STOREY: a pair of rooms the table says are walkable, whose
  # boxes touch. Two rooms connected but NOT touching get no door drawn and are
  # a fault worth seeing -- the edge is still on the graph above, which is where
  # it shows up.
  def doorways_among(rooms)
    rooms.combination(2).filter_map do |a, b|
      next unless connected?(a.node.location, b.node.location)

      doorway_between(a, b)
    end
  end

  def connected?(a, b)
    connections.any? do |row|
      (row.location_id == a.id && row.connected_location_id == b.id) ||
        (row.location_id == b.id && row.connected_location_id == a.id)
    end
  end

  # WHERE THE GAP IN A WALL TWO ROOMS SHARE IS DRAWN, and the one piece of
  # arithmetic on this page that is neither `Location::Box`'s nor pixels. See the
  # class header, including what it would take to move it onto `Box`.
  #
  # The intervals are half-open (`Location::Box`), so two rooms that share a wall
  # do not overlap: one's far edge is the other's near edge, exactly. The door is
  # `DOOR_PACES` wide at the middle of whatever length of wall they actually
  # share, and there is no door at all when they share a corner and nothing else.
  def doorway_between(a, b)
    wall = shared_wall(a.box, b.box)
    return nil if wall.nil?

    axis, at, from, to = wall
    middle = (from + to) / 2.0
    half = DOOR_PACES / 2.0
    near = [ middle - half, from ].max
    far = [ middle + half, to ].min
    reading = "#{a.name} <-> #{b.name}"

    if axis == :x
      Doorway.new(x1: at * PACE, y1: near * PACE, x2: at * PACE, y2: far * PACE, reading: reading)
    else
      Doorway.new(x1: near * PACE, y1: at * PACE, x2: far * PACE, y2: at * PACE, reading: reading)
    end
  end

  # The wall two boxes share, as an axis, the coordinate it stands at and the
  # stretch of it they have in common -- or nil when they do not touch, or touch
  # at a corner alone. Coordinates are in PACES and relative to the plan's own
  # origin, which the caller has already subtracted.
  def shared_wall(a, b)
    if a.x + a.width == b.x || b.x + b.width == a.x
      at = a.x + a.width == b.x ? a.x + a.width : b.x + b.width
      overlap = [ [ a.y, b.y ].max, [ a.y + a.depth, b.y + b.depth ].min ]
      return [ :x, at, *overlap ] if overlap.last > overlap.first
    elsif a.y + a.depth == b.y || b.y + b.depth == a.y
      at = a.y + a.depth == b.y ? a.y + a.depth : b.y + b.depth
      overlap = [ [ a.x, b.x ].max, [ a.x + a.width, b.x + b.width ].min ]
      return [ :y, at, *overlap ] if overlap.last > overlap.first
    end

    nil
  end

  # A STAIR IS AN EDGE, so it is read off the connections and not off a shape:
  # every doorway out of a room on this storey whose `travel_method` is
  # "taking stairs" and whose far end stands on a different storey. Drawn in the
  # room it leaves from, so it appears once on each of the two plans it joins.
  def stairs_from(rooms)
    rooms.flat_map do |room|
      stair_ends_from(room.node.location).filter_map do |far|
        next if far.box.nil? || far.box.z == room.box.z

        Stair.new(x: room.x + (room.width / 2.0), y: room.y + (room.height / 2.0),
                  up: far.box.z > room.box.z,
                  reading: "stairs to #{far.name}, storey #{far.box.z}")
      end
    end
  end

  # WHERE THE STAIRS OUT OF THIS ROOM GO, once each. A door is two rows and both
  # of them name this room, so the far ends are collapsed before they are drawn
  # -- otherwise one stairwell would be marked twice on the same plan.
  def stair_ends_from(location)
    connections.filter_map { |row| far_end(row, location.id) if stair_from?(row, location) }
               .uniq.filter_map { |id| locations_by_id[id] }
  end

  def stair_from?(row, location)
    row.travel_method == "taking stairs" &&
      (row.location_id == location.id || row.connected_location_id == location.id)
  end

  def far_end(row, id)
    row.location_id == id ? row.connected_location_id : row.location_id
  end
end
