namespace :eval do
  desc "Price the first-read inscription corpus without calls"
  task inscription_estimate: :environment do
    puts JSON.pretty_generate(Eval::Inscription.estimate)
  end

  desc "Buy the fixed-facts inscription set: SET=name REPS=n EVAL_MODEL=id"
  task inscription: :environment do
    path = Eval.root.join(ENV.fetch("SET"), Eval::Inscription::RESULTS)
    bench = Eval::Inscription::Bench.new(model: ENV.fetch("EVAL_MODEL", Eval::Cost.default_model),
                                        reps: ENV.fetch("REPS", Eval::Noise::MIN_RUNS))
    puts JSON.pretty_generate(Eval::Inscription.estimate(model: ENV.fetch("EVAL_MODEL", Eval::Cost.default_model),
                                                       reps: Integer(ENV.fetch("REPS", Eval::Noise::MIN_RUNS))))
    puts Eval::Inscription::Report.board(bench.run(path))
  end

  desc "Re-score a stored inscription set offline: SET=name"
  task inscription_score: :environment do
    puts Eval::Inscription::Report.board(Eval::Inscription::Report.load_set(ENV.fetch("SET")))
  end
  task inscription_board: :inscription_score

  desc "Compare inscription sets offline: BEFORE=name AFTER=name"
  task inscription_compare: :environment do
    puts Eval::Inscription::Report.compare(Eval::Inscription::Report.load_set(ENV.fetch("BEFORE")),
                                          Eval::Inscription::Report.load_set(ENV.fetch("AFTER")))
  end

  desc "Digest every fixed inscription request without a model call"
  task inscription_digest: :environment do
    requests = Eval::Inscription.requests
    puts JSON.pretty_generate(request_identity: Eval::RequestIdentity.of(requests),
                              cases: requests.transform_values { |request| Eval::RequestIdentity.of(request) })
  end
end
