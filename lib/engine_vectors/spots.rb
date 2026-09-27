# `Location::Spot.inside`: one cell of a box, drawn x then y from one generator.
module EngineVectors::Spots
  SOURCES = [ "app/models/location/spot.rb", "app/models/roll.rb" ].freeze
  NOTES = "Each case opens Random.new(seed) and calls Location::Spot.inside(box, rng:) `draws` times in " \
          "a row on that one generator; output is the spots drawn, in order, as [x, y]. The first " \
          "case is the one-cell box the model test pins.".freeze

  def self.constants_table = {}

  def self.cases
    golden = [ EngineVectors.case_for("one cell", input(Location::Box.new(x: 4, y: 9, z: 0, width: 1, depth: 1), 1, 1),
                                      draw(Location::Box.new(x: 4, y: 9, z: 0, width: 1, depth: 1), 1, 1)) ]
    boxes = [
      [ 0, 0, 0, 3, 3 ], [ 7, 2, 1, 5, 3 ], [ 0, 0, -1, 18, 18 ], [ 12, 0, 2, 1, 9 ],
      [ -4, -6, 0, 6, 2 ], [ 3, 3, 0, 2, 1 ], [ 0, 0, 0, 100, 100 ], [ 5, 5, 0, 9, 17 ]
    ].map { |x, y, z, width, depth| Location::Box.new(x: x, y: y, z: z, width: width, depth: depth) }
    rolled = boxes.product((0...40).to_a).map do |box, seed|
      EngineVectors.case_for("#{box} seed #{seed}", input(box, seed, 3), draw(box, seed, 3))
    end
    golden + rolled
  end

  def self.input(box, seed, draws) = { "box" => box.to_h.transform_keys(&:to_s), "seed" => seed, "draws" => draws }

  def self.draw(box, seed, draws)
    rng = Random.new(seed)
    Array.new(draws) { Location::Spot.inside(box, rng: rng).then { |spot| [ spot.x, spot.y ] } }
  end
end
