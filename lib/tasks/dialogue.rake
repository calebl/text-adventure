# Same named-set vocabulary as the other benches. Paid runs require an explicit
# scratch DATABASE_URL and durable EVAL_BUDGET_FILE; reads and replay are free.
namespace :eval do
  desc "Run the fixed NPC study; SET=name CORPUS=main|bystander EVAL_LIVE=1 EVAL_BUDGET_FILE=path, TRIAL=1 for one repetition read by hand"
  task dialogue: :environment do
    trial = ENV["TRIAL"] == "1"
    Eval::Dialogue::Bench.new(corpus: ENV.fetch("CORPUS", "main"))
                         .run(Eval.root.join(ENV.fetch("SET")), reps: ENV.fetch("REPS", trial ? 1 : Eval::Noise::MIN_RUNS).to_i, trial: trial)
  end

  %w[score board].each do |verb|
    desc "#{verb.capitalize} a dialogue set offline; SET=name ANNOTATIONS=optional.json"
    task "dialogue_#{verb}" => :environment do
      annotations = JSON.parse(File.read(ENV["ANNOTATIONS"])) if ENV["ANNOTATIONS"].present?
      result = Eval::Dialogue::Result.load(Eval.set_path(ENV.fetch("SET")), annotations: annotations)
      puts JSON.pretty_generate(result.board)
    end
  end

  desc "Compare dialogue sets; BEFORE=name AFTER=name, optional BEFORE_ANNOTATIONS/AFTER_ANNOTATIONS"
  task dialogue_compare: :environment do
    sides = %w[BEFORE AFTER].map do |side|
      annotations = JSON.parse(File.read(ENV["#{side}_ANNOTATIONS"])) if ENV["#{side}_ANNOTATIONS"].present?
      Eval::Dialogue::Result.load(Eval.set_path(ENV.fetch(side)), annotations: annotations)
    end
    puts JSON.pretty_generate(sides.first.compare(sides.last))
  end

  desc "Rebuild every kept dialogue request offline and check full identity; SET=name"
  task dialogue_digest: :environment do
    result = Eval::Dialogue::Result.load(Eval.set_path(ENV.fetch("SET")))
    mismatches = result.rows.filter_map do |row|
      rebuilt = Eval::Dialogue::Version.rebuild(row)
      row.values_at("id", "rep") unless row.fetch("request_digest") == rebuilt.fetch("request_digest")
    end
    puts JSON.pretty_generate(corpus_digest: Eval::Dialogue.digest(result.data.fetch("corpus", "main")), mismatches: mismatches)
    abort "Dialogue requests changed" if mismatches.any?
  end
end
