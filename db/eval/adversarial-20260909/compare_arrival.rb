# Offline replay of the saved human annotations. Uses the repository's unchanged
# exact rank test; no model judge or new general prose scorer is introduced.
require "json"
root = Pathname.new(__dir__)
key = JSON.parse(root.join("arrival-reading-key.json").read)
annotations = JSON.parse(root.join("arrival-independent-annotations.json").read).fetch("annotations").index_by { |row| row.fetch("id") }
raise "Missing annotations" unless annotations.keys.sort == key.keys.sort
raw = %w[before after].to_h { |arm| [ arm, JSON.parse(root.join("arrival-#{arm}.json").read).fetch("rows") ] }
raise "All four repetitions of each fixed case are required" unless raw.values.all? { |rows| rows.size == 12 && rows.group_by { |row| row.fetch("case") }.values.all? { |group| group.map { |row| row.fetch("rep") }.sort == [ 1, 2, 3, 4 ] } }
metrics = {
  "description_contradiction" => ->(row) { row.dig("description", "contradiction") == true ? 1 : 0 },
  "description_fact_missing_strict" => ->(row) { row.dig("description", "required_fact_acknowledged") == true ? 0 : 1 },
  "description_fact_missing_inclusive" => ->(row) { row.dig("description", "required_fact_acknowledged") == false ? 1 : 0 },
  "summary_fact_missing_strict" => ->(row) { row.dig("summary", "required_fact_acknowledged") == true ? 0 : 1 }
}
comparisons = []
[ "all", "dead_resident", "carried_key", "crossing_harm" ].each do |scope|
  metrics.each do |metric, reading|
    values = %w[before after].to_h do |arm|
      [ arm, (1..4).map do |rep|
        selected = key.select { |_id, identity| identity["arm"] == arm && identity["rep"] == rep && (scope == "all" || identity["case"] == scope) }
        selected.keys.sum { |id| reading.call(annotations.fetch(id)) }.fdiv(selected.size)
      end ]
    end
    verdict = Eval::Noise.compare(metric, values.fetch("before"), values.fetch("after"))
    comparisons << { scope: scope, metric: metric, lower_is_better: true, values: values, **verdict.to_h }
  end
end
%w[failed_call description_words seconds].each do |metric|
  values = raw.transform_values do |rows|
    (1..4).map do |rep|
      group = rows.select { |row| row.fetch("rep") == rep }
      group.sum do |row|
        case metric
        when "failed_call" then row["error"] ? 1 : 0
        when "description_words" then row["description"].to_s.split.size
        when "seconds" then row["elapsed"].to_f
        end
      end.fdiv(group.size)
    end
  end
  comparisons << { scope: "all", metric: metric, values: values, **Eval::Noise.compare(metric, values.fetch("before"), values.fetch("after")).to_h }
end
report = { model: "mistralai/mistral-medium-3.1", repetitions: 4, cases_per_repetition: 3,
          annotations: "arrival-independent-annotations.json", second_reading: "arrival-root-annotations.json",
          notes: [ "Description and summary assessed separately; summaries are not the prose shown to players.",
                  "Three corpse descriptions are ambiguous; strict and inclusive acknowledgment both reported.",
                  "No exact injury acknowledgment in any player description. The new deterministic toll notice is separately tested and not counted as model prose.",
                  "Focused cases do not establish general realism or prove absence of contradictions." ],
          comparisons: comparisons }
root.join("arrival-comparison.json").write(JSON.pretty_generate(report) + "\n")
comparisons.select { |row| row[:scope] == "all" }.each do |row|
  puts "#{row[:metric]}: #{row[:before][:median]} -> #{row[:after][:median]} #{row[:outcome].to_s.upcase} p=#{row[:p_value]}"
end
