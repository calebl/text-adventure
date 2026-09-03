# THE AUTOMATED HALF OF THE EVALUATION LOOP.
#
#   rake eval:run        generate runs across the three seeded worlds, then score them
#   rake eval:score      score a set again -- offline, free, and the only half CI could run
#   rake eval:compare    two sets, with a verdict per check: REAL, NOISE or INCONCLUSIVE
#   rake eval:estimate   what a sweep of this shape would cost, before it runs
#   rake eval:manifest   the files that constitute the measurement, and a digest of each
#
# GENERATION SPENDS MONEY AND MUST NEVER RUN IN CI. It needs `OPENROUTER_API_KEY`
# and refuses to start without one; scoring needs nothing at all. `EVALUATION.md`
# is the protocol.
namespace :eval do
  desc "Generate runs across the three seeded worlds and print a board. REPS=5 TURNS=all SET=<name> YES=1"
  task run: :environment do
    set = EvalTasks.generate!
    next if set.nil?

    puts
    EvalTasks.score!(set)
  end

  desc "Score a generated set again -- offline, no model call. Usage: rake eval:score SET=<name> SAMPLE=24"
  task score: :environment do
    EvalTasks.score!(EvalTasks.set_name)
  end

  desc "Compare two scored sets and give a verdict per check. Usage: rake eval:compare BEFORE=<set> AFTER=<set>"
  task compare: :environment do
    before = ENV["BEFORE"].presence or abort "BEFORE=<set> is the run set to compare against. #{EvalTasks.available_sets}"
    after = ENV["AFTER"].presence or abort "AFTER=<set> is the run set to judge. #{EvalTasks.available_sets}"

    Eval::Comparison.new(Eval::RunSet.load(Eval.set_path(before)), Eval::RunSet.load(Eval.set_path(after))).print
  end

  desc "The null check: split ONE set's runs in half and compare them. Everything should read NOISE. Usage: rake eval:null SET=main"
  task null: :environment do
    set = Eval::RunSet.load(Eval.set_path(EvalTasks.set_name))
    first, second = EvalTasks.halve(set)

    puts "THE NULL CHECK. Both halves are runs of the SAME code over the SAME worlds, so any"
    puts "verdict of REAL below is the protocol manufacturing a result out of sampling noise."
    puts "This is the answer to \"can this measurement ever say no\", and it should be run"
    puts "whenever the rule in Eval::Noise is changed."
    puts
    Eval::Comparison.new(first, second).print

    manufactured = (Eval::TUNING + [ Eval::HELD_OUT ]).flat_map do |story|
      Eval::Comparison.new(first, second).verdicts(stories: [ story ]).select(&:real?)
    end
    puts
    puts manufactured.any? ? "FAILED: #{manufactured.map(&:code).join(", ")} came out REAL on two halves of one set." :
                             "PASSED: nothing came out REAL. The protocol did not invent a difference."
  end

  desc "What a sweep of this shape would cost, before it runs. Usage: rake eval:estimate REPS=5 TURNS=all"
  task estimate: :environment do
    puts EvalTasks.estimate
    puts "Measured, not modelled: #{Eval::Cost::PER_TURN[:input]} in / #{Eval::Cost::PER_TURN[:output]} out per turn," \
         " from 12 real whole-run transcripts. See Eval::Cost."
  end

  desc "The files that constitute the measurement, with a digest of each -- the manifest a future improving agent leaves alone"
  task manifest: :environment do
    puts "THE MEASUREMENT. An agent improving the game changes none of these."
    puts "Declared in Eval::MEASUREMENT_FILES. Documented, not enforced -- see EVALUATION.md."
    puts
    Eval::MEASUREMENT_FILES.each do |relative|
      path = Rails.root.join(relative)
      digest = File.exist?(path) ? Digest::SHA256.file(path).hexdigest[0, 16] : "MISSING"
      puts format("  %-16s %s", digest, relative)
    end
    puts
    puts "Snapshot this before a change and again after: nothing in it may have moved."
  end

  # Namespaced under a module rather than defined at rake top level, where the
  # methods would land on Object. The same reason `game.rake` has `Helpers`.
  module EvalTasks
    extend self

    DEFAULT_REPS = 5
    SPEND_CEILING = 1.00

    # Seconds one run may take before it is killed. See `#spawn_run`.
    RUN_TIMEOUT = (ENV["EVAL_RUN_TIMEOUT"].presence || 1200).to_i

    # THE SET TO ACT ON: the one named, or the most recent one generated. A
    # sweep with no `SET=` lands in a timestamped directory, so "score the thing
    # I just ran" has to mean something without the operator copying a
    # timestamp back out of the output.
    def set_name
      return ENV["SET"] if ENV["SET"].present?

      newest = Dir.glob(Eval.root.join("*", "runs")).max_by { |path| File.mtime(path) }
      abort "No run sets under #{Eval::ROOT}. Generate one first: rake eval:run" if newest.nil?

      File.basename(File.dirname(newest))
    end

    def reps = (ENV["REPS"].presence || DEFAULT_REPS).to_i

    def turns = ENV["TURNS"].presence&.then { |value| value == "all" ? nil : value.to_i }

    def stories
      named = ENV["STORIES"].presence&.split(",")&.map(&:strip)
      return Eval::STORIES if named.blank?

      unknown = named - Eval::STORIES
      abort "unknown world(s): #{unknown.join(", ")}. The sweep plays #{Eval::STORIES.join(", ")}." if unknown.any?
      named
    end

    def turns_per_run = turns || Eval::Script.all.map(&:size).max

    # THE MODEL THE APP SHIPS WITH, not whatever the shell has pinned. A sweep
    # is a measurement of the game as it is configured for a player, and
    # `OPENROUTER_MODEL` in a developer's `.envrc` would quietly make it a
    # measurement of something else. `EVAL_MODEL=` overrides, on purpose, and
    # the estimate is priced on whichever of the two will actually answer.
    def pinned_model = ENV["EVAL_MODEL"].presence || Eval::Cost.default_model

    def estimate = Eval::Cost.estimate(runs: stories.size * reps, turns: turns_per_run, model: pinned_model)

    def available_sets
      found = Dir.glob(Eval.root.join("*", Eval::RunSet::SCORES)).map { |path| File.basename(File.dirname(path)) }.sort
      found.any? ? "Scored sets: #{found.join(", ")}." : "There are no scored sets yet -- run `rake eval:run` first."
    end

    # ---------------------------------------------------------- generation
    def generate!
      abort "OPENROUTER_API_KEY is not set. Generation is the only half of this loop that spends money, " \
            "and it will not run without a key. Scoring needs none: `rake eval:score`." if ENV["OPENROUTER_API_KEY"].blank?
      abort "Generation must not run in the test environment." if Rails.env.test?

      priced = estimate
      puts "ESTIMATE: #{priced}"
      if priced.dollars > SPEND_CEILING && ENV["YES"] != "1"
        abort "That is over the $#{format("%.2f", SPEND_CEILING)} ceiling this task will spend unattended. " \
              "Re-run with YES=1, or lower REPS / TURNS."
      end

      set = ENV["SET"].presence || Time.current.utc.strftime("%Y%m%d-%H%M%S")
      directory = Eval.set_path(set)
      FileUtils.mkdir_p(directory.join("runs"))
      FileUtils.mkdir_p(directory.join("log"))

      base = Eval.root.join("base.sqlite3")
      system(*rails_runner, "script/eval_base.rb", exception: true) unless File.exist?(base)

      pinned = pinned_model
      puts "Generating #{stories.size} worlds x #{reps} reps into #{directory}, pinned on #{pinned}."
      puts

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      (1..reps).each do |rep|
        stories.each_slice(concurrency) do |batch|
          batch.map { |story| spawn_run(story, rep, directory, base, pinned) }.each { |pid| Process.wait(pid) }
        end
      end
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      puts
      puts format("Generated %d runs in %.1f minutes.", stories.size * reps, elapsed / 60)
      directory
    end

    # THREE AT A TIME BY DEFAULT: one per world, so the three worlds of one
    # repetition run together and a repetition is never half-finished. More
    # than that and OpenRouter starts rate-limiting, which shows up as
    # rotations and puts a second model's prose in the corpus.
    def concurrency = (ENV["CONCURRENCY"].presence || 3).to_i

    def spawn_run(story, rep, directory, base, pinned)
      slug = WorldSeed.slug(story)
      database = directory.join("runs", "#{slug}-r#{rep}.sqlite3")
      FileUtils.cp(base, database)

      environment = {
        "EVAL_DB" => database.to_s, "EVAL_STORY" => story, "EVAL_REP" => rep.to_s,
        "EVAL_OUT" => directory.join("runs", "#{slug}-r#{rep}.json").to_s,
        "OPENROUTER_MODEL" => pinned
      }
      environment["EVAL_TURNS"] = turns.to_s if turns

      log = directory.join("log", "#{slug}-r#{rep}.log")
      # A CAP ON ONE RUN, because a batch waits on all of its children and a
      # single hung provider call otherwise stops the sweep rather than costing
      # it one run. Eleven turns of the slowest model in the rotation is a few
      # minutes; twenty is a hang. A killed run leaves no manifest and is simply
      # absent from the scoring, which is the honest outcome -- the board counts
      # the runs it has.
      spawn(environment, "timeout", RUN_TIMEOUT.to_s, *rails_runner, "script/eval_run.rb",
            out: log.to_s, err: [ :child, :out ])
    end

    def rails_runner = [ Rails.root.join("bin/rails").to_s, "runner" ]

    # THE SET SPLIT IN TWO, alternating by repetition so each half holds every
    # world and neither is "the early runs". Used by `eval:null` only.
    def halve(set)
      odd, even = set.runs.partition { |run| run.rep.odd? }

      [ Eval::RunSet.new(name: "#{set.name} (odd reps)", runs: odd, path: set.path),
        Eval::RunSet.new(name: "#{set.name} (even reps)", runs: even, path: set.path) ]
    end

    # ---------------------------------------------------------- scoring
    def score!(set)
      directory = set.is_a?(Pathname) ? set : Eval.set_path(set)
      abort "No run set at #{directory}. #{available_sets}" unless File.directory?(directory)

      puts "Scoring #{directory}. No model call, no API key, no network."
      scored = Eval::RunSet.score(directory)
      puts
      Eval::Board.new(scored).print(sample: (ENV["SAMPLE"].presence || Eval::Board::DEFAULT_SAMPLE).to_i)
      scored
    end
  end
end
