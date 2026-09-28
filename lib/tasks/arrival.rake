# A sibling bench with the existing run/score/board/compare/digest vocabulary.
# Paid runs require an explicit scratch database and a persistent budget ledger.
# CORPUS=reactions buys and digests the room reacting to the arrival
# (`Eval::Arrival::Reactions`) instead of the arrival corpus.
module ArrivalTasks
  SUITES = { "main" => "Eval::Arrival", "reactions" => "Eval::Arrival::Reactions" }.freeze

  def self.suite
    SUITES.fetch(ENV.fetch("CORPUS", "main")) { |name| abort "No arrival corpus #{name.inspect}. There is: #{SUITES.keys.join(", ")}" }
          .constantize
  end
end

namespace :eval do
  desc "Buy fixed arrival calls: SET=name CORPUS=main|reactions EVAL_LIVE=1 EVAL_BUDGET_FILE=path DATABASE_URL=sqlite3:tmp/..."
  task arrival: :environment do
    suite = ArrivalTasks.suite
    estimate = suite.estimate(reps: Integer(ENV.fetch("REPS", Eval::Noise::MIN_RUNS)))
    puts JSON.pretty_generate(estimate)
    Eval::Arrival::Bench.new(suite).run(Eval.root.join(ENV.fetch("SET")), reps: estimate.fetch(:reps))
  end

  desc "Re-score stored arrival fields offline: SET=name ANNOTATIONS=optional.json"
  task arrival_score: :environment do
    annotations = ENV["ANNOTATIONS"] ? JSON.parse(File.read(ENV.fetch("ANNOTATIONS"))) : {}
    result = Eval::Arrival::Result.load(Eval.set_path(ENV.fetch("SET", Eval::Arrival::BASELINE.basename.to_s)), annotations: annotations)
    puts result.board
    puts Eval::Arrival::Result.study_board
  end

  desc "Print the arrival board offline: SET=name"
  task arrival_board: :arrival_score

  desc "Compare arrival sets through Eval::Noise: BEFORE=name AFTER=name"
  task arrival_compare: :environment do
    before = Eval::Arrival::Result.load(Eval.set_path(ENV.fetch("BEFORE")))
    after = Eval::Arrival::Result.load(Eval.set_path(ENV.fetch("AFTER")))
    puts JSON.pretty_generate(before.compare(after))
  end

  desc "Rebuild every arrival request identity offline, without a model call. CORPUS=main|reactions"
  task arrival_digest: :environment do
    suite = ArrivalTasks.suite
    suite.cases.each do |kase|
      suite.stage.open(kase) do |stage|
        puts "#{kase.fetch('id')} #{Eval::RequestIdentity.label(Eval::RequestIdentity.of([ stage.request ]))}"
      end
    end
  end

  task estimate: :environment do
    puts "Arrival baseline: #{Eval::Arrival.estimate.to_json}"
  end
end
