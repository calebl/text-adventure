# `Location::Parameters`: the tables behind a building's picked labels, and
# what each pick resolves to.
module EngineVectors::Parameters
  SOURCES = [ "app/models/location/parameters.rb", "app/models/location.rb" ].freeze
  NOTES = "`constants` is every table in its key order. A resolve case gives the picks as written (an " \
          "unknown key or value falls back) and the resolved labels and numbers, with danger_for and " \
          "hazard_share_for for storeys -3..3 as [storey, answer] pairs. A footprint case is " \
          "Parameters#footprint on Random.new(seed): [width, depth], or null when the pick has no inside.".freeze

  P = Location::Parameters

  def self.constants_table
    {
      "inside" => EngineVectors.pairs(P::INSIDE),
      "rooms_a_band_promises" => EngineVectors.pairs(P::ROOMS_A_BAND_PROMISES),
      "storeys_above" => EngineVectors.pairs(P::STOREYS_ABOVE),
      "storeys_below" => EngineVectors.pairs(P::STOREYS_BELOW),
      "danger" => EngineVectors.pairs(P::DANGER),
      "ladder" => P::LADDER,
      "gradient" => EngineVectors.pairs(P::GRADIENT),
      "hazards" => P::HAZARDS,
      "hazard_die" => P::HAZARD_DIE,
      "hazard_share" => P::HAZARD_SHARE
    }
  end

  def self.cases
    resolves + footprints
  end

  def self.resolves
    picks = [ {}, { "inside" => "nonsense", "danger" => "deadly", "hazard" => "lava" }, { "gradient" => nil } ]
    picks += P::DANGER.keys.product(P::GRADIENT.keys, [ P::NO_HAZARD, *Location::HAZARDS.keys ]).map do |danger, gradient, hazard|
      { "danger" => danger, "gradient" => gradient, "hazard" => hazard }
    end
    picks += P::INSIDE.keys.zip(P::STOREYS_ABOVE.keys.cycle, P::STOREYS_BELOW.keys).map do |inside, above, below|
      { "inside" => inside, "storeys_above" => above, "storeys_below" => below }
    end
    picks.each_with_index.map { |pick, index| EngineVectors.case_for("resolve #{index}", { "kind" => "resolve", "picks" => pick }, resolve(pick)) }
  end

  def self.resolve(pick)
    parameters = P.from(pick)
    storeys = (-3..3).to_a
    {
      "inside" => parameters.inside, "inside?" => parameters.inside?,
      "storeys_above" => parameters.storeys_above, "storeys_below" => parameters.storeys_below,
      "above" => parameters.above, "below" => parameters.below,
      "danger" => parameters.danger, "gradient" => parameters.gradient,
      "hazard" => parameters.hazard, "hazard?" => parameters.hazard?,
      "danger_for" => storeys.map { |storey| [ storey, parameters.danger_for(storey) ] },
      "hazard_share_for" => storeys.map { |storey| [ storey, parameters.hazard_share_for(storey) ] }
    }
  end

  def self.footprints
    P::INSIDE.keys.product((0...60).to_a).map do |inside, seed|
      EngineVectors.case_for("footprint #{inside} seed #{seed}",
                             { "kind" => "footprint", "picks" => { "inside" => inside }, "seed" => seed },
                             P.from("inside" => inside).footprint(Random.new(seed)))
    end
  end
end
