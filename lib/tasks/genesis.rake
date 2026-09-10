namespace :eval do
  desc "Fixed genesis boundaries, scored against records, on one pinned model. Usage: rake eval:genesis SET=<name> [REPS=] [MODEL=]"
  task genesis: :environment do
    abort "The genesis bench must not buy calls in the test environment." if Rails.env.test?
    abort "OPENROUTER_API_KEY is required" if ENV["OPENROUTER_API_KEY"].blank?
    name = ENV.fetch("SET")
    directory = Eval.root.join(name)
    abort "set already exists: #{directory}" if directory.join(Eval::Genesis::RESULTS).exist?
    model = ENV.fetch("MODEL", Eval::Cost.default_model)
    reps = Integer(ENV.fetch("REPS", Eval::Noise::MIN_RUNS))
    puts "Estimated ceiling at registry prices: $#{Eval::Genesis.estimate(reps: reps, models: [ model ])}"
    result = Eval::Genesis::Bench.new(model: model, reps: reps).run(directory: directory)
    puts Eval::Genesis::Board.new(result).lines
  end

  desc "Score a stored genesis set again — offline, no model call, no key. Usage: rake eval:genesis_score SET=<name>"
  task genesis_score: :environment do
    result = Eval::Genesis::Result.load(Eval.set_path(ENV.fetch("SET")))
    puts Eval::Genesis::Board.new(result).lines
  end

  desc "Stored genesis sets as tables. Usage: rake eval:genesis_board SETS=a,b"
  task genesis_board: :environment do
    ENV.fetch("SETS", Eval::Genesis::BASELINE).split(",").each do |name|
      puts Eval::Genesis::Board.new(Eval::Genesis::Result.load(Eval.set_path(name))).lines
    end
  end

  desc "Two genesis sets with a noise verdict per figure. Usage: rake eval:genesis_compare BEFORE=<set> AFTER=<set>"
  task genesis_compare: :environment do
    results = %w[BEFORE AFTER].map { |key| Eval::Genesis::Result.load(Eval.set_path(ENV.fetch(key))) }
    puts Eval::Genesis::Comparison.new(*results).lines
  end

  desc "Genesis request digests over system, user, history and emitted schema — offline, no key. Usage: rake eval:genesis_digest"
  task genesis_digest: :environment do
    puts JSON.pretty_generate(Eval::Genesis::Version.offline)
  end
end
