require "json"
require "digest"

directory = File.dirname(__FILE__)
audit = JSON.parse(File.read(File.join(directory, "experience-audit.json")))
word_count = ->(text) { text.to_s.scan(/[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*/u).length }
arms = %w[before after].to_h do |arm|
  source = JSON.parse(File.read(File.join(directory, "experience-#{arm}.json")))
  raise "Incomplete arm" unless source.fetch("reps") >= 4 && source.fetch("results").length == source.fetch("reps") * 4
  results = source.fetch("results").map do |row|
    label = audit.fetch(arm).fetch("#{row.fetch('case')}:#{row.fetch('rep')}")
    raise "Missing judgement" unless [ true, false ].include?(label.fetch("experience_contradiction"))
    raise "Failed model call is not a successful case" if row["error"] || row["fallback"] || row.fetch("calls").any? { |call| call["error"] }
    row.merge(label).merge("narration_words" => word_count.call(row.fetch("narration")),
                          "reaction_words" => row.fetch("reaction").values.sum { |value| word_count.call(value) })
  end
  repetitions = results.group_by { |row| row.fetch("rep") }.sort.to_h.transform_values do |rows|
    raise "Missing case" unless rows.map { |row| row.fetch("case") }.sort == %w[old-betrayal old-promise own-injury unwitnessed-injury]
    %w[experience_contradiction narration_words reaction_words].to_h do |metric|
      [ metric, rows.sum { |row| [ true, false ].include?(row.fetch(metric)) ? (row.fetch(metric) ? 1 : 0) : row.fetch(metric) }.fdiv(rows.length) ]
    end
  end
  calls = results.flat_map { |row| row.fetch("calls") }
  [ arm, { source: source.fetch("source"), corpus: source.fetch("corpus"), fixtures: source.fetch("fixtures_sha256"),
           repetitions: repetitions, contradictions: results.count { |row| row.fetch("experience_contradiction") },
           cases: results.group_by { |row| row.fetch("case") }.transform_values do |rows|
             { contradictions: rows.count { |row| row.fetch("experience_contradiction") },
               key_given: rows.count { |row| row.fetch("carries_key") },
               specific_experience_references: rows.count { |row| row.fetch("specific_experience_referenced") } }
           end,
           calls: calls.length, model_ids: calls.map { |row| row.fetch("actual_model") }.uniq,
           input_tokens: calls.sum { |row| row.fetch("input_tokens") }, output_tokens: calls.sum { |row| row.fetch("output_tokens") },
           provider_cost_usd: calls.sum { |row| row["provider_cost_usd"].to_f },
           provider_cost_missing: calls.count { |row| row["provider_cost_usd"].nil? },
           conservative_usage_usd: calls.sum { |row| row.fetch("usage_upper_micros") }.fdiv(1_000_000) } ]
end
raise "Changed fixtures" unless arms.values.map { |arm| arm.values_at(:corpus, :fixtures) }.uniq.one?
verdicts = %w[experience_contradiction narration_words reaction_words].map do |metric|
  samples = arms.values.map { |arm| arm.fetch(:repetitions).values.map { |row| row.fetch(metric) } }
  Eval::Noise.compare(metric, *samples).to_h
end
result = { arms: arms, verdicts: verdicts,
           limitations: [ "Manual judgments were not blinded; all raw outputs and labels are retained.",
                          "The promise request reminds the NPC of the promise; both arms lend the key, and neither names the medicine. No improvement is claimed for that case.",
                          "Neither arm claims to witness the remote attack. Both invent some unrelated local news; this is outside the targeted experience contradiction metric and remains a prose-verification concern.",
                          "Lexical retrieval can miss paraphrases. Recollections are attributed beliefs and do not authorize state changes.",
                          "Four repetitions of these fixtures do not establish general NPC realism." ] }
File.write(File.join(directory, "experience-comparison.json"), JSON.pretty_generate(result))
puts JSON.pretty_generate(verdicts)
