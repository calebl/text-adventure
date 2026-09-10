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
  STUDY = Rails.root.join("db/eval/adversarial-20260909")
  RESULTS = "dialogue.json".freeze

  def self.cases = JSON.parse(CORPUS.read).fetch("cases")
  def self.model = JSON.parse(STUDY.join("npc-after.json").read).fetch("model")
  def self.digest = Digest::SHA256.hexdigest(CORPUS.read)

  # Price the preserved two-pass receipts at today's registry rates. The added
  # cases inherit this shape; it is an estimate, not a spending guard. Budget
  # reserves a conservative bound before each actual request, including errors.
  def self.estimate(reps: Eval::Noise::MIN_RUNS)
    price = Eval::Cost.price(model)
    raise ArgumentError, "Load the model registry before pricing dialogue" unless
      price.input_per_million.positive? && price.output_per_million.positive?

    rows = JSON.parse(STUDY.join("npc-after.json").read).fetch("results")
    input = rows.sum { |r| r.fetch("calls").sum { |c| c.fetch("input_tokens") + c.fetch("cached_tokens", 0).to_i } }.fdiv(rows.size)
    output = rows.sum { |r| r.fetch("calls").sum { |c| c.fetch("output_tokens") } }.fdiv(rows.size)
    { model: model, cases: cases.size, reps: reps, calls: cases.size * reps * 2,
      input_per_case: input, output_per_case: output,
      estimated_usd: price.of(input * cases.size * reps, output * cases.size * reps),
      input_per_million: price.input_per_million, output_per_million: price.output_per_million }
  end
end
