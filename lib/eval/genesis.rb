# FIXED BOUNDARIES OF WORLD CREATION, NOT A JUDGE OF FICTION.
# Each producer receives a kept upstream answer, never another repetition's
# invention. The first-screen case visits its genesis boundaries in order;
# room realization and arrival remain their own instruments. This bench changes
# no production prompt. Believability, identity in prose and quest quality need
# the separately commissioned human lab.
module Eval::Genesis
  CORPUS = Rails.root.join("test/fixtures/files/genesis_corpus.yml")
  WORLD = Rails.root.join("test/fixtures/files/worlds/the-iron-gate-descends.yml")
  RESULTS = "genesis.json".freeze
  BASELINE = "genesis-before".freeze

  def self.corpus = Corpus.load
  def self.digest(corpus = self.corpus) = Version.digest([ corpus.cases.map(&:to_h), WorldSeed.parse(File.read(WORLD)) ])

  # A token allowance, not a historical measurement: price the actual assembled
  # request bytes conservatively and allow the schema's maximum strings plus
  # JSON overhead for the answer. Unknown registry prices must never look free.
  def self.estimate(cases: corpus.cases, reps: Eval::Noise::MIN_RUNS, models: [ Eval::Cost.default_model ])
    requests = cases.flat_map { |kase| Stage.open(kase) { |stage| stage.requests.map(&:identity) } }
    input = requests.sum { |request| JSON.generate(request).bytesize }
    output = requests.sum { |request| output_allowance(request.fetch("schema").fetch("schema")) }
    Eval::Classifier::Arm.all(models).sum do |arm|
      price = arm.price
      raise ArgumentError, "unpriced model #{arm}; run rake ruby_llm:load_models" if !arm.free? && price.of(1, 1).zero?

      price.of(input * reps, output * reps)
    end
  end

  def self.output_allowance(schema)
    case schema["type"]
    when "object" then 128 + schema.fetch("properties").values.sum { |child| output_allowance(child) }
    when "array" then 32 + schema.fetch("maxItems", 8) * output_allowance(schema.fetch("items"))
    when "string" then schema.fetch("maxLength", 1200) + 16
    else 16
    end
  end
end
