# Offline, from the kept full readings. Rebuild the legacy-only comparison and
# first figures for new cases without rewriting either historical baseline.
require "zlib"
root = Rails.root.join("doc/evidence/ta-bench-realization-branches")
name = "branches-to-corpus-after"
kept = Eval.kept_root.join(name)
full = Zlib::GzipReader.open(kept.join("readings.json.gz")) { |file| JSON.parse(file.read) }
legacy = Eval::Realization.corpus.subset { |kase| kase.staging.empty? }
old = Eval::Realization::Result.load(Eval.kept_root.join("exits-quantifier-after"))
raise "the legacy cases have changed" unless Eval::Realization.digest(legacy) == old.corpus_digest
ids = legacy.cases.map(&:id)
passes = full.fetch("passes").map do |pass|
  rows = pass.fetch("readings").select { |row| ids.include?(row.fetch("id")) }
  Eval::Realization::Result::Stored.new({ "arm" => pass.fetch("arm"), "rep" => pass.fetch("rep"),
    "readings" => rows }.merge(Eval::Realization::Result.figures_of(rows)))
end
subset = Eval::Realization::Result.new(name: "branches-to-corpus-legacy", corpus_size: legacy.size,
  corpus_digest: Eval::Realization.digest(legacy), prompt_digest: full.fetch("prompt_digest"),
  instructions_digest: full.fetch("instructions_digest"), prompt_shapes: full.fetch("prompt_shapes"),
  prompt_stable: full.fetch("prompt_stable"), arms: full.fetch("arms"), reps: full.fetch("reps"),
  passes: passes, recorded_at: full.fetch("recorded_at"))
subset.summary.write!(Eval.root.join("branches-to-corpus-legacy"))
File.open(root.join("legacy-compare.txt"), "w") do |io|
  Eval::Realization::Comparison.new(old, subset, io: io).print
end
branch_rows = full.fetch("passes").flat_map { |pass| pass.fetch("readings") }.reject { |row| ids.include?(row.fetch("id")) }
figures = branch_rows.group_by { |row| row.fetch("id") }.transform_values do |rows|
  rows.map { |row| { "rep" => row.fetch("rep") }.merge(Eval::Realization::Result.figures_of([ row ])) }
end
File.write(root.join("first-figures.json"), JSON.pretty_generate(figures))
puts "Rebuilt legacy comparison and first figures from kept readings, offline."
