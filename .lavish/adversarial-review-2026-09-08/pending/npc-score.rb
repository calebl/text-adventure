# Offline scorer for the predeclared NPC protocol; run with bin/rails runner.
require "json"
require "digest"

directory = ENV.fetch("EVAL_RESULTS_DIR")
labels = JSON.parse(File.read(File.join(directory, "npc-contradiction-audit.json")))
fields = %w[pre_thought pre_feeling action post_feeling post_thought inner_resolution].freeze
words = ->(text) { text.to_s.scan(/[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*/u).size }
expected = {
  "give-owned-key" => [ true, false, false ],
  "follow-through-door" => [ false, true, false ],
  "honor-ceasefire" => [ false, false, false ],
  "refuse-trusted-key" => [ false, false, false ],
  "cannot-give-absent-item" => [ false, false, false ]
}.freeze

arms = %w[before after].to_h do |arm|
  path = File.join(directory, "npc-#{arm}.json")
  source = JSON.parse(File.read(path))
  raise "Wrong model" unless source.fetch("model") == "mistralai/mistral-medium-3.1"
  raise "Need four repetitions" unless source.fetch("reps") >= 4
  raise "Cannot score preflight" if source.fetch("preflight")
  rows = source.fetch("results").map do |row|
    audit = labels.fetch(arm).fetch("#{row.fetch('case')}:#{row.fetch('rep')}")
    raise "Incomplete manual judgment" unless [ true, false ].include?(audit.fetch("contradiction"))
    raise "Positive judgments need evidence" if audit["contradiction"] && (audit["excerpt"].to_s.empty? || audit["reason"].to_s.empty?)
    row.merge("state_failure" => row.values_at("carries_key", "following", "foe") != expected.fetch(row.fetch("case")),
              "exchange_failure" => !!(row["error"] || row.fetch("calls").any? { |call| call["error"] } || row["narration"].to_s.strip.empty?),
              "contradiction" => audit.fetch("contradiction"),
              "reaction_words" => fields.sum { |field| words.call(row.fetch("reaction", nil)&.fetch(field, nil)) },
              "narration_words" => words.call(row["narration"]))
  end
  repetitions = rows.group_by { |row| row.fetch("rep") }.sort.to_h.transform_values do |group|
    raise "Missing or duplicated fixture" unless group.map { |row| row.fetch("case") }.sort == expected.keys.sort
    %w[state_failure exchange_failure contradiction reaction_words narration_words].to_h do |metric|
      total = group.sum { |row| [ true, false ].include?(row.fetch(metric)) ? (row.fetch(metric) ? 1 : 0) : row.fetch(metric) }
      [ metric, total.fdiv(group.size) ]
    end
  end
  raise "Missing repetitions" unless repetitions.keys == (1..source.fetch("reps")).to_a
  calls = rows.flat_map { |row| row.fetch("calls") }
  [ arm, { corpus: source.fetch("corpus"), sha256: Digest::SHA256.file(path).hexdigest,
           repetitions: repetitions, rows: rows.map { |row| row.slice("case", "rep", "action", "status", "state_failure", "exchange_failure", "contradiction", "reaction_words", "narration_words") },
           calls: calls.size, models: calls.map { |call| call["actual_model"] }.uniq,
           input_tokens: calls.sum { |call| call["input_tokens"].to_i },
           output_tokens: calls.sum { |call| call["output_tokens"].to_i },
           provider_cost_usd: calls.sum { |call| call["provider_cost_usd"].to_f },
           provider_cost_missing: calls.count { |call| call["provider_cost_usd"].nil? },
           registry_cost_usd: calls.sum { |call| call["registry_cost_usd"].to_f },
           usage_upper_usd: calls.sum { |call| call["usage_upper_micros"].to_i }.fdiv(1_000_000) } ]
end
raise "Corpus changed" unless arms.values.map { |arm| arm.fetch(:corpus) }.uniq.one?
verdicts = %w[state_failure exchange_failure contradiction reaction_words narration_words].map do |metric|
  samples = arms.values.map { |arm| arm.fetch(:repetitions).values.map { |rep| rep.fetch(metric) } }
  Eval::Noise.compare(metric, *samples).to_h
end
output = { protocol: "npc-protocol.md", arms: arms, verdicts: verdicts }
File.write(File.join(directory, "npc-comparison.json"), JSON.pretty_generate(output))
puts JSON.pretty_generate(verdicts)
