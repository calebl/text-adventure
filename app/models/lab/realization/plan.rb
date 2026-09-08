# A BUILDING A SAMPLE PRODUCED, DRAWN OUT OF THE STORED ROW AND NOTHING ELSE.
#
# WHY IT HAS TO EXIST. `Story::Map` draws a place's inside off the `Location`
# rows, and a lab draw has none: `Lab::Realization::Runner` stages its copy of
# the world inside a rolled-back transaction, so the moment the sample is saved
# the building is gone and the stored `row` is all that is left. So this reads
# the plan back out of `Eval::Realization::Stage::Standing#rooms_laid_out` --
# which is why slice 2 put `x`, `y` and the doors on that row in the first
# place.
#
# THE CAPTAIN'S REASON, and it is the whole of the slice: *he looks at a
# building's shape instead of reading its table.* A table of storeys and extents
# is a description of a floor plan that a person has to build in their head, and
# the fault this programme keeps hitting is not a wrong number, it is a SHAPE
# nobody looked at (`Story::Map`'s header). One draw of a warren that turns out
# to be a corridor of five rooms in a line is visible in a glance and invisible
# in the table.
#
# IT IS NOT A SECOND RENDERER AND NOT A SECOND GEOMETRY. Every value it returns
# is a `Story::Map` value -- `Interior`, `Storey`, `Room`, `Doorway`, `Stair` --
# built with `Story::Map.plan_bounds`, `Story::Map.doorway_between`,
# `Story::Map::PACE` and `Location::Box`, and rendered through
# `app/views/map/_floor_plan.html.erb` unchanged. What this class adds is the
# translation from a stored hash to those values, and that is all it may ever
# add: a rectangle drawn here that the map page would draw differently would be
# two answers to where a room is.
#
# A STORED SET WITHOUT THE KEYS IS SIMPLY NOT DRAWABLE, which is
# `Eval::Realization::Scorer::Reading#records_the_way_back?`'s rule and its
# reason. Every sample drawn before slice 2 has `storey`, `width` and `depth` on
# each room and no `x` -- and a plan guessed from an extent with no position
# would be a picture of a building nobody generated, which is worse than no
# picture. `.for` returns nil on such a row and the page says why. The gate is
# the KEY and not the value: an `x` of zero is a room against the west wall.
#
# THE FOOTPRINT IS THE ROOMS' OWN UNION, and that is a reading rather than a
# guess: the rooms tile the footprint EXACTLY (`Location::Interior`'s doctrine
# -- no corridors and no gaps, because a gap is a region of the plane nothing
# owns), so the smallest rectangle holding all of them IS the plane they were
# divided out of. Nothing is stored beside them and nothing needs to be; a
# second record of the extent could only disagree with the rooms.
#
# IT IS NOT PASSED AS NIL, and that matters for one sentence:
# `app/views/map/_floor_plan.html.erb` reads a missing footprint as a FAULT --
# rooms with no plane to read them in, which `rake game:doctor` reports -- and
# on the map page it is one. Here it would be a fault message about a design
# decision, which is the worst kind of warning: the true one nobody can act on.
#
# A ROOM OF A LAB DRAW IS ALWAYS A STUB AND NOBODY IS EVER STANDING IN IT.
# `Location::Interior` writes children with a placeholder name and nothing walks
# into them, and there is no playthrough at all -- so `#stub?` is true and
# `#here?` is false for every room, off the state of the draw rather than off a
# guess. `#dangerous?` and `#hazardous?` are read off the stored columns, which
# are the same columns `Location` answers those two from.
class Lab::Realization::Plan
  # WHAT A `Story::Map::Room` ASKS ITS `node` FOR, and nothing more. Five
  # answers, which is the contract `app/views/map/_floor_plan.html.erb` states
  # in its header -- so this stands in for a `Location` row that no longer
  # exists without pretending to be one.
  Standin = Data.define(:name, :stub, :here, :dangerous, :hazardous) do
    def stub? = stub
    def dangerous? = dangerous
    def hazardous? = hazardous
  end

  # THE PLAN FOR ONE SAMPLE'S READING, or nil when there is nothing to draw --
  # no rooms at all, or rooms stored before positions were. Nil rather than an
  # empty plan, so the page has one question to ask.
  def self.for(reading, name:)
    rooms = Array(reading.rooms)
    return nil if rooms.empty? || rooms.any? { |room| !positioned?(room) }

    new(rooms, name: name).interior
  end

  # WHETHER ONE STORED ROOM SAYS WHERE IT IS. The key and not the value, for the
  # header's reason.
  def self.positioned?(room) = room.key?("x") && room.key?("y")

  def initialize(rooms, name:)
    @rooms = rooms
    @name = name
  end

  def interior
    boxes = drawn.map { |_stored, room| room.box }
    footprint = [ boxes.map { |box| box.x + box.width }.max,
                  boxes.map { |box| box.y + box.depth }.max ]
    origin_x, origin_y, plan_width, plan_height = Story::Map.plan_bounds(footprint, drawn.map(&:last))

    storeys = drawn.group_by { |_stored, room| room.box.z }.sort_by { |z, _| -z }.map do |z, on_this_storey|
      build_storey(z, on_this_storey.map { |stored, room| [ stored, reframe(room, origin_x, origin_y) ] })
    end

    Story::Map::Interior.new(place: Standin.new(name: @name, stub: false, here: false,
                                                dangerous: false, hazardous: false),
                             footprint: footprint, origin_x: origin_x, origin_y: origin_y,
                             plan_width: plan_width, plan_height: plan_height, storeys: storeys)
  end

  private

  # EVERY ROOM AS A `Story::Map::Room` AT THE RECORDS' OWN ORIGIN, PAIRED WITH
  # THE HASH IT CAME FROM. The pair rather than a lookup: a `Story::Map::Room`
  # has no slot for a stored index and inventing one for the lab's sake would
  # change what a room is on the map page too, so the two travel together for
  # as long as the doors need both.
  #
  # REFRAMED AFTERWARDS AND NOT HERE, because `Story::Map.plan_bounds` has to see
  # the boxes as the rows wrote them before it can say where the origin is --
  # which is the order `Story::Map#build_interior` does it in.
  def drawn
    @drawn ||= @rooms.each_with_index.map { |room, index| [ room, build_room(room, index) ] }
  end

  def build_room(room, index)
    box = Location::Box.new(x: room["x"].to_i, y: room["y"].to_i, z: room["storey"].to_i,
                            width: room["width"].to_i, depth: room["depth"].to_i)

    Story::Map::Room.new(node: standin_for(room, index), box: box, plan_box: box,
                         x: 0, y: 0, width: 0, height: 0)
  end

  # DANGER AND HAZARD READ OFF `Location`'S OWN TABLES and not off the strings.
  # `Location#dangerous?` is `DANGERS.fetch(danger, 0).positive?` and
  # `Location#hazardous?` needs a key the catalogue has AND a die -- so these are
  # those two readings applied to a row whose record is gone, rather than a third
  # opinion about what a dangerous room is.
  def standin_for(room, index)
    Standin.new(name: room["name"].presence || "room #{index + 1}",
                stub: true, here: false,
                dangerous: Location::DANGERS.fetch(room["danger"], 0).positive?,
                hazardous: Location::HAZARDS.key?(room["hazard"]) && room["hazard_die"].present?)
  end

  # THE SAME ARITHMETIC `Story::Map#build_room` DOES, and it is respelt rather
  # than borrowed only because that method reads a `Location` row to get its box.
  # Every number in it is `Location::Box`'s and `Story::Map::PACE`'s, so the two
  # cannot drift.
  def reframe(room, origin_x, origin_y)
    plan_box = room.box.with(x: room.box.x - origin_x, y: room.box.y - origin_y)

    room.with(plan_box: plan_box,
              x: plan_box.x * Story::Map::PACE, y: plan_box.y * Story::Map::PACE,
              width: plan_box.width * Story::Map::PACE, height: plan_box.depth * Story::Map::PACE)
  end

  # THE DOORS AND THE STAIRS THIS STOREY HOLDS, off the stored indices and never
  # off the geometry. `Location::Interior` opens a serpentine backbone and then
  # throws a die at every other shared wall, so two rooms that touch usually
  # have no door between them -- a plan that drew every shared wall as a doorway
  # would be drawing a building the layout refused to build.
  def build_storey(z, pairs)
    Story::Map::Storey.new(z: z, rooms: pairs.map(&:last),
                           doorways: doorways_among(pairs),
                           stairs: stairs_from(pairs, z))
  end

  # A DOOR ONCE, NOT TWICE. A door is two rows, so `doors_to` names it on both
  # rooms of the pair; the lower index is the one that draws it. A door whose far
  # end is on another storey is not drawn here and cannot be: it is a stair, and
  # `#rooms_laid_out` has already put it in the other list.
  def doorways_among(pairs)
    here = pairs.to_h { |stored, room| [ stored["index"], room ] }

    pairs.flat_map do |stored, room|
      Array(stored["doors_to"]).filter_map do |far|
        next if far <= stored["index"].to_i

        other = here[far]
        next if other.nil?

        Story::Map.doorway_between(room, other)
      end
    end
  end

  # A STAIR IS A MARK IN THE ROOM IT LEAVES FROM, drawn on each of the two
  # storeys it joins -- `Story::Map#stairs_from`'s rule, and the reason is the
  # captain's third ruling of 2026-09-06: a floor is its own plane, so there is
  # nothing vertical to draw. Which way it goes is read off the far room's
  # stored storey.
  def stairs_from(pairs, z)
    pairs.flat_map do |stored, room|
      Array(stored["stairs_to"]).filter_map do |far|
        other = by_index[far]
        next if other.nil? || other["storey"].to_i == z

        Story::Map::Stair.new(x: room.centre_x, y: room.centre_y,
                              up: other["storey"].to_i > z,
                              reading: "stairs to #{other["name"]}, storey #{other["storey"]}")
      end
    end
  end

  def by_index = @by_index ||= @rooms.to_h { |room| [ room["index"], room ] }
end
