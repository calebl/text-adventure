# `Location::Box`: a room's place on its storey, and every question two boxes answer.
module EngineVectors::Boxes
  SOURCES = [ "app/models/location/box.rb" ].freeze
  NOTES = "Each case is a pair of boxes, `a` and `b`, and every answer Box gives about them with `a` " \
          "as the receiver: shared_wall is [axis, line, from, to] or null; wall_towards and " \
          "bearing_of are words or null; shared_ground is a box or null; metres and to_s are a's " \
          "own; inside_footprint is a.inside_footprint?(footprint); contains is a.contains?(spot).".freeze

  B = Location::Box

  def self.constants_table
    {
      "metres_per_pace" => B::METRES_PER_PACE, "minimum_doorway" => B::MINIMUM_DOORWAY,
      "walls" => B::WALLS, "bearing_share" => B::BEARING_SHARE
    }
  end

  def self.cases
    anchors = [ B.new(x: 0, y: 0, z: 0, width: 6, depth: 4), B.new(x: 3, y: 3, z: 1, width: 3, depth: 5),
                B.new(x: 0, y: 0, z: 0, width: 18, depth: 18), B.new(x: 2, y: 5, z: -1, width: 1, depth: 1),
                B.new(x: 7, y: 0, z: 0, width: 5, depth: 5) ]
    offsets = [ -6, -3, -1, 0, 1, 3, 4, 6, 7, 12 ]
    others = offsets.product(offsets.first(8), [ 0, 1 ]).each_with_index.map do |(x, y, z), index|
      B.new(x: x, y: y, z: z, width: [ 1, 3, 4, 6, 2 ].fetch(index % 5), depth: [ 4, 1, 3, 6, 2, 5 ].fetch(index % 6))
    end
    pairs = anchors.product(others).select.with_index { |_, index| index % 2 == 0 }
    pairs.each_with_index.map { |(a, b), index| one(a, b, index) }
  end

  def self.one(a, b, index)
    footprint = [ 12, 9 ]
    spot = Location::Spot.new(x: b.x, y: b.y)
    shared_ground = a.shared_ground(b)
    EngineVectors.case_for("pair #{index}",
                           { "a" => hash(a), "b" => hash(b), "footprint" => footprint, "spot" => [ spot.x, spot.y ] },
                           { "overlaps" => a.overlaps?(b), "shares_ground" => a.shares_ground?(b),
                             "shares_a_wall" => a.shares_a_wall?(b),
                             "shared_wall" => a.shared_wall(b)&.then { |axis, *rest| [ axis.to_s, *rest ] },
                             "wall_towards" => a.wall_towards(b), "shared_ground" => shared_ground && hash(shared_ground),
                             "bearing_of" => a.bearing_of(b), "metres" => a.metres,
                             "inside_footprint" => a.inside_footprint?(*footprint), "contains" => a.contains?(spot),
                             "paces_to" => a.paces_to(b), "to_s" => a.to_s })
  end

  def self.hash(box) = box.to_h.transform_keys(&:to_s)
end
