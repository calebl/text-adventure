# `Roll`: how a seed is built and what each kind of draw returns from it.
module EngineVectors::Dice
  SOURCES = [ "app/models/roll.rb" ].freeze
  NOTES = "Seed cases give Roll.seed's five parts and the seed, as a decimal string. Draw cases open " \
          "Random.new(seed) once and apply `ops` in order to that one generator; output[i] is op i's " \
          "answer. die: Roll.die(sides). pool: Roll.pool(count, sides). one_of: Roll.one_of over " \
          "(0...size), so the answer is the index drawn. weighted: Roll.weighted_one_of over " \
          "(0...weights.size) with those weights, answering the index. range: rng.rand(min..max). " \
          "shuffle: (0...size).to_a.shuffle(random: rng).".freeze

  # One op list, run on every seed: every kind of draw, every edge a kind has
  # (one side, one choice, zero and negative weights, a range wider than one
  # 32-bit word), and a second pass so a draw's effect on the next is recorded.
  OPS = [
    { "op" => "die", "sides" => 6 },
    { "op" => "die", "sides" => 20 },
    { "op" => "die", "sides" => 1 },
    { "op" => "pool", "count" => 3, "sides" => 6 },
    { "op" => "pool", "count" => 1, "sides" => 8 },
    { "op" => "one_of", "size" => 5 },
    { "op" => "one_of", "size" => 1 },
    { "op" => "one_of", "size" => 1000 },
    { "op" => "weighted", "weights" => [ 3, 0, 1 ] },
    { "op" => "weighted", "weights" => [ 0, 0 ] },
    { "op" => "weighted", "weights" => [ -2, 5, 1 ] },
    { "op" => "weighted", "weights" => [ 1, 2, 3, 4, 5, 6, 7, 8 ] },
    { "op" => "range", "min" => 18, "max" => 80 },
    { "op" => "range", "min" => -5, "max" => 5 },
    { "op" => "range", "min" => 1, "max" => 2**40 },
    { "op" => "range", "min" => 0, "max" => 2**32 - 1 },
    { "op" => "shuffle", "size" => 7 },
    { "op" => "shuffle", "size" => 1 },
    { "op" => "die", "sides" => 6 },
    { "op" => "one_of", "size" => 3 },
    { "op" => "range", "min" => 1, "max" => 100 }
  ].freeze

  # Seeds that take each branch of Random.new: one 32-bit word, several words,
  # a top word of exactly one, and negatives (whose magnitude is used).
  EDGE_SEEDS = [
    0, 1, 2, 2**31 - 1, 2**31, 2**32 - 1, 2**32, 2**32 + 1, 2**33, 2**33 + 7,
    2**63 - 1, 2**63, 2**64 - 1, 2**64, 2**64 + 1, 2**65 + 12_345, 2**96, 2**100 + 3,
    -1, -2, -(2**32), -(2**40) - 9, -(2**70),
    1_000_003, 100_000_007, 1_767_225_600 * Roll::AT
  ].freeze

  SEED_PARTS = [
    { story: 0 },
    { story: 1 },
    { story: 7, playthrough: 3 },
    { story: 7, playthrough: 3, at: 1_767_225_600 },
    { story: 42, at: 1_767_225_600, sequence: 12, kind: Roll::INTERIOR },
    { story: 0, sequence: 3_266_443_110, kind: Roll::POPULATION },
    { story: 5, sequence: Location::Danger::SEQUENCE_BASE + 17 },
    { story: 2**40, playthrough: 2**33, at: 2**34, sequence: 2**35, kind: 2**36 },
    { story: -3, playthrough: 1, at: -60, sequence: 2, kind: Roll::CAST }
  ].freeze

  def self.constants_table
    {
      "multipliers" => EngineVectors.pairs("story" => Roll::STORY, "playthrough" => Roll::PLAYTHROUGH,
                                           "at" => Roll::AT, "sequence" => Roll::SEQUENCE, "kind" => Roll::KIND),
      "kinds" => EngineVectors.pairs(%w[THROW INTERIOR ITEM_POSITION CHARACTER_POSITION FOOTPRINT
                                        POPULATION VOLITION CAST].to_h { |name| [ name, Roll.const_get(name) ] })
    }
  end

  def self.cases
    seed_cases + draw_cases
  end

  def self.seed_cases
    parts = SEED_PARTS + (0...40).map { |n| { story: n, playthrough: n % 3, at: n * 3_600, sequence: n * 7, kind: n % 9 } }
    parts.each_with_index.map do |part, index|
      EngineVectors.case_for("seed #{index}", part.transform_keys(&:to_s), Roll.seed(**part).to_s)
    end
  end

  def self.draw_cases
    seeds = EDGE_SEEDS + (0...300).to_a + (0...40).map { |n| Roll.seed(story: n + 1, at: 1_767_225_600 + n * 60, sequence: n) }
    seeds.each_with_index.map do |seed, index|
      EngineVectors.case_for("draws #{index}", { "seed" => seed.to_s, "ops" => OPS }, run(Random.new(seed)))
    end
  end

  def self.run(rng)
    OPS.map do |op|
      case op.fetch("op")
      when "die" then Roll.die(op.fetch("sides"), rng: rng)
      when "pool" then Roll.pool(op.fetch("count"), op.fetch("sides"), rng: rng)
      when "one_of" then Roll.one_of((0...op.fetch("size")).to_a, rng: rng)
      when "weighted"
        weights = op.fetch("weights")
        Roll.weighted_one_of((0...weights.size).to_a, weights, rng: rng)
      when "range" then rng.rand(op.fetch("min")..op.fetch("max"))
      when "shuffle" then (0...op.fetch("size")).to_a.shuffle(random: rng)
      end
    end
  end
end
