# Fixed destination records, one Scene::Generator call, two separate readings.
# Prompt::Corpus::Case cannot prepare destination wounds, tolls or a world
# opening without a turn; a sibling keeps its existing corpus identities intact.
# Run/score/board/compare/digest use the same vocabulary as the dialogue bench.
# The retained study supplies facts, not copied prompt builders. No prompt is
# edited here. Semantic contradiction beyond placed facts, revisit recognition
# quality and prose quality remain unmeasured. The stale main move set belongs
# to the separate main re-baseline task.
module Eval::Arrival
  CORPUS = Rails.root.join("test/fixtures/files/arrival_corpus.json")
  STUDY = Rails.root.join("db/eval/adversarial-20260909")
  RESULTS = "arrival.json".freeze
  BASELINE = Rails.root.join("db/eval/arrival-branches")

  def self.cases = JSON.parse(CORPUS.read).fetch("cases")
  def self.model = JSON.parse(STUDY.join("arrival-after.json").read).fetch("model")
  def self.digest = Digest::SHA256.hexdigest(CORPUS.read)

  def self.estimate(reps: Eval::Noise::MIN_RUNS)
    price = Eval::Cost.price(model)
    raise ArgumentError, "Load the model registry before pricing arrival" unless
      price.input_per_million.positive? && price.output_per_million.positive?

    tokens = Eval::Prompt::PER_CALL.fetch("arrival")
    { model: model, cases: cases.size, reps: reps, calls: cases.size * reps,
      input_per_case: tokens[:input], output_per_case: tokens[:output],
      estimated_usd: price.of(tokens[:input] * cases.size * reps, tokens[:output] * cases.size * reps),
      input_per_million: price.input_per_million, output_per_million: price.output_per_million }
  end
end
