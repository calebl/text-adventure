# WHAT A SWEEP WILL COST, BEFORE IT RUNS, AND WHAT IT ACTUALLY COST AFTER.
#
# Generation is the only part of this loop that spends money, and the rule is
# the captain's: estimate before spending, report the actual figure. Both come
# out of records the app already holds -- `models.pricing` is the RubyLLM
# registry `db/seeds.rb` fills, and the token counts are the `messages` rows
# every `BaseAgent` call writes. So neither number needs the network and
# neither is a guess about what a provider charges.
#
# THE ESTIMATE IS A MEASUREMENT, not a model of one. `PER_TURN` is what a real
# eleven-turn run of the app's own loop cost in tokens, taken from the four-arm
# whole-run sweep of 2026-09-02 (`data/ta-conversation-read-2/lab`, 12 runs,
# 132 turns). It is stated per turn so a sweep of any shape can be priced, and
# it is deliberately the HIGHEST of the four arms -- an estimate that comes in
# under is a nasty surprise and an estimate that comes in over is not.
#
# PROMPT CACHING WAS MEASURED AND BUYS US NOTHING, which is worth writing down
# because it is the obvious lever and it is shut. OpenRouter does cache for
# `mistralai/mistral-medium-3.1` automatically -- no `cache_control` breakpoints
# to send, and `ruby_llm` already reads `prompt_tokens_details.cached_tokens`
# off the response -- but there is a MINIMUM CACHEABLE PROMPT of 2,048 tokens
# and every prompt this app sends is under it:
#
#   one long passage of distinct prose,     1,941 tokens ->     0 cached
#     sent twice a few seconds apart        2,418 tokens -> 2,304 cached
#   real prompts lifted out of a finished   745..1,309 tokens
#     run: 3 agents x 3 repeats, 18 calls              ->     0 cached, all 18
#
# Cached blocks are 256 tokens and a write costs nothing extra. The sweep of
# 2026-09-03 averaged 615 input tokens over 1,112 calls, so nothing qualifies.
# And the ceiling is small even if it did: the shared prefixes between
# consecutive calls of one agent are 44.8% of a 24-run sweep's input (the
# classifier's prompt is 82% identical call to call), which at $0.04 against
# $0.40 would take a $0.4712 bill to $0.3608. Reproduce the measurement with
# `script/cache_probe.rb`; it spends about a cent.
#
# ONE CONSEQUENCE, IF PROMPTS EVER GROW PAST 2,048 TOKENS: `ruby_llm` reports
# `input_tokens` as `prompt_tokens - cached - cache_write`, and the `messages`
# table has no column for the cached half. A cached call therefore writes a
# SMALLER input count, and `#actual` below would under-report the bill, because
# cached tokens are cheaper and not free. Nothing caches today, so nothing is
# wrong today -- but a prompt that grows past the floor makes the spend figure
# quietly optimistic rather than loudly broken.
module Eval::Cost
  extend self

  # Tokens per turn, measured. Input dominates and does not shrink: an arrival
  # inlines the universe, so a run's input is mostly the world it is set in.
  PER_TURN = { input: 1_800, output: 300 }.freeze

  Price = Data.define(:model, :input_per_million, :output_per_million) do
    def of(input_tokens, output_tokens)
      (input_tokens * input_per_million + output_tokens * output_per_million) / 1_000_000.0
    end
  end

  UNKNOWN = Price.new(model: "unknown", input_per_million: 0.0, output_per_million: 0.0)

  # The registry's price for a model id, or a zero price that says so. A model
  # the registry has never heard of costs nothing HERE, which is wrong and is
  # reported as `unpriced` rather than hidden -- see `#actual`.
  def price(model_id)
    row = Model.find_by(model_id: model_id)
    standard = row&.pricing&.dig("text_tokens", "standard")
    return UNKNOWN if standard.blank?

    Price.new(model: model_id,
              input_per_million: standard["input_per_million"].to_f,
              output_per_million: standard["output_per_million"].to_f)
  end

  # WHAT A SWEEP OF THIS SHAPE SHOULD COST. Priced on the model that will
  # actually answer -- the first of `BaseAgent::REMOTE_MODEL_IDS`, which is what
  # the runner pins -- because rotation is the exception and pricing for it
  # would overstate every run that never rotates.
  Estimate = Data.define(:model, :runs, :turns, :input_tokens, :output_tokens, :dollars) do
    def to_s
      format("%d runs x %d turns = %d turns, ~%s tokens in / %s out, on %s: about $%.2f",
             runs, turns, runs * turns,
             input_tokens.to_fs(:delimited), output_tokens.to_fs(:delimited), model, dollars)
    end
  end

  def estimate(runs:, turns:, model: default_model)
    total = runs * turns
    input = total * PER_TURN[:input]
    output = total * PER_TURN[:output]

    Estimate.new(model:, runs:, turns:, input_tokens: input, output_tokens: output,
                 dollars: price(model).of(input, output))
  end

  # THE APP'S OWN FIRST MODEL, deliberately not `remote_model_options.first` --
  # that one honours `OPENROUTER_MODEL` from the shell, and a sweep that priced
  # and ran whatever a developer had pinned would not be a measurement of the
  # game anybody is shipping.
  def default_model = BaseAgent::REMOTE_MODEL_IDS.first

  # WHAT IT REALLY COST, from the token counts the run wrote down. `usage` is
  # the shape `script/eval_run.rb` records: one row per model that answered.
  Actual = Data.define(:rows, :dollars, :unpriced) do
    def calls = rows.sum { |row| row[:calls].to_i }
    def input_tokens = rows.sum { |row| row[:input_tokens].to_i }
    def output_tokens = rows.sum { |row| row[:output_tokens].to_i }
  end

  def actual(usage)
    rows = Array(usage).map { |row| row.transform_keys(&:to_sym) }
    unpriced = []
    dollars = rows.sum do |row|
      found = price(row[:model])
      unpriced << row[:model] if found == UNKNOWN
      found.of(row[:input_tokens].to_i, row[:output_tokens].to_i)
    end

    Actual.new(rows:, dollars:, unpriced: unpriced.uniq)
  end
end
