# A standing version of the retained NPC study, with the same two passes and
# human contradiction rubric. This is a sibling of Prompt because that bench
# scores one displayed passage; here a character choice changes records before
# an exchange narrator sees the receipt. Run/score/board/compare/digest retain
# the existing evaluation vocabulary without weakening Prompt's talk exclusion.
#
# This measures bounded actions and displayed contradictions, not voice, memory
# fidelity across turns, long-term character behavior, or personality. History
# bytes are versioned; that is identity coverage, not a memory quality score.
module Eval::Dialogue
  CORPUS = Rails.root.join("test/fixtures/files/dialogue_corpus.json")
  # A BYSTANDER WHO SPOKE UP UNASKED while the exchange happened, which the
  # exchange's narrator is told through the moment it is handed. A second file,
  # because `.digest` is over the first and a case added there would cost its
  # kept set; a set names the corpus it measured, and one that names none is
  # the first's.
  BYSTANDER_CORPUS = Rails.root.join("test/fixtures/files/dialogue_bystander_corpus.json")
  CORPORA = { "main" => CORPUS, "bystander" => BYSTANDER_CORPUS }.freeze
  STUDY = Rails.root.join("db/eval/adversarial-20260909")
  RESULTS = "dialogue.json".freeze
  BASELINE = "desires-dialogue-20260919".freeze
  BYSTANDER_BASELINE = "dialogue-bystander-2026-09-28".freeze

  def self.cases(corpus = "main") = JSON.parse(CORPORA.fetch(corpus).read).fetch("cases")
  def self.model = JSON.parse(STUDY.join("npc-after.json").read).fetch("model")
  def self.digest(corpus = "main") = Digest::SHA256.hexdigest(CORPORA.fetch(corpus).read)

  # Price the preserved two-pass receipts at today's registry rates. The added
  # cases inherit this shape; it is an estimate, not a spending guard. Budget
  # reserves a conservative bound before each actual request, including errors.
  def self.estimate(reps: Eval::Noise::MIN_RUNS, corpus: "main")
    price = Eval::Cost.price(model)
    raise ArgumentError, "Load the model registry before pricing dialogue" unless
      price.input_per_million.positive? && price.output_per_million.positive?

    rows = JSON.parse(STUDY.join("npc-after.json").read).fetch("results")
    input = rows.sum { |r| r.fetch("calls").sum { |c| c.fetch("input_tokens") + c.fetch("cached_tokens", 0).to_i } }.fdiv(rows.size)
    output = rows.sum { |r| r.fetch("calls").sum { |c| c.fetch("output_tokens") } }.fdiv(rows.size)
    size = cases(corpus).size
    { model: model, cases: size, reps: reps, calls: size * reps * 2,
      input_per_case: input, output_per_case: output,
      estimated_usd: price.of(input * size * reps, output * size * reps),
      input_per_million: price.input_per_million, output_per_million: price.output_per_million }
  end
end
