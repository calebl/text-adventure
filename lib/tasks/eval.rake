# THE AUTOMATED HALF OF THE EVALUATION LOOP.
#
#   rake eval:run        generate runs across the three seeded worlds, then score them
#   rake eval:score      score a set again -- offline, free, and the only half CI could run
#   rake eval:compare    two sets, with a verdict per check: REAL, NOISE or INCONCLUSIVE
#   rake eval:estimate   what a sweep of this shape would cost, before it runs
#   rake eval:manifest   the files that constitute the measurement, and a digest of each
#
# AND THE CLASSIFIER'S OWN BENCH, which reads an answer against a hand-written
# label rather than prose against the records:
#
#   rake eval:classifier            replay the labelled corpus through the real classifier
#   rake eval:classifier_offline    the same corpus with no model at all -- free, and in CI
#   rake eval:classifier_omission   the `also_named` omission rate alone (PR 102 finding F4)
#   rake eval:classifier_compare    two bench runs, with a verdict per figure
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

  desc "Read one whole run as prose, every turn, flagged or not. Usage: rake 'eval:read[The Salt Assizes,1]' SET=main"
  task :read, [ :story, :rep ] => :environment do |_task, args|
    story = args[:story].presence or abort "Which world? rake 'eval:read[#{Eval::HELD_OUT}]'. The sweep plays: #{Eval::STORIES.join(", ")}."
    matched = Eval::STORIES.find { |title| title.casecmp?(story) } or abort "Unknown world #{story.inspect}. The sweep plays: #{Eval::STORIES.join(", ")}."

    Eval::Transcript.read(Eval.set_path(EvalTasks.set_name), story: matched, rep: (args[:rep].presence || 1).to_i).print
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

  desc "Replay the labelled classifier corpus through the real classifier. REPS=4 MODELS=a,b SET=<name> SAMPLE=20 YES=1"
  task classifier: :environment do
    ClassifierTasks.run!
  end

  desc "The classifier corpus through the fixed grammar with NO MODEL -- free, offline, the floor a call is bought against"
  task classifier_offline: :environment do
    corpus = Eval::Classifier.corpus
    puts "#{corpus.size} labelled lines, #{corpus.positions.size} positions, no model call and no key."
    puts
    Eval::Classifier::Report.new(
      Eval::Classifier::Result.new(corpus_size: corpus.size, arms: [], reps: 0, passes: []),
      floor: Eval::Classifier::Offline.new(corpus: corpus).summary
    ).offline_floor
  end

  desc "The `also_named` omission rate on its own -- the two-noun lines only. Usage: rake eval:classifier_omission REPS=1"
  task classifier_omission: :environment do
    ClassifierTasks.omission!
  end

  desc "Every classifier bench set on disk as one cross-model table. Usage: rake eval:classifier_board SETS=a,b"
  task classifier_board: :environment do
    Eval::Classifier::Board.for_sets(ENV["SETS"].presence&.split(",")&.map(&:strip)).print
  rescue ArgumentError => error
    abort error.message
  end

  desc "Two classifier bench runs, with a verdict per figure -- including two DIFFERENT models. " \
       "Usage: rake eval:classifier_compare BEFORE=<set> AFTER=<set> [BEFORE_MODEL=] [AFTER_MODEL=]"
  task classifier_compare: :environment do
    before = ENV["BEFORE"].presence or abort "BEFORE=<set> is the bench run to compare against. #{ClassifierTasks.available_sets}"
    after = ENV["AFTER"].presence or abort "AFTER=<set> is the bench run to judge. #{ClassifierTasks.available_sets}"

    Eval::Classifier::Comparison.new(Eval::Classifier::Result.load(Eval.set_path(before)),
                                     Eval::Classifier::Result.load(Eval.set_path(after)),
                                     before_model: ENV["BEFORE_MODEL"].presence,
                                     after_model: ENV["AFTER_MODEL"].presence).print
  rescue Eval::Classifier::Comparison::Unpairable => error
    abort error.message
  end

  # THE CLASSIFIER BENCH'S HALF OF THIS FILE. Separate from `EvalTasks` because
  # it shares none of it: no run databases, no spawned processes, no per-world
  # concurrency, and a spend two orders of magnitude smaller.
  module ClassifierTasks
    extend self

    # FOUR, BECAUSE FOUR IS `Eval::Noise::MIN_RUNS`. The prose loop's default is
    # five runs and its floor is four; here the two coincide, so a bench run
    # taken at the default is a run a later `rake eval:classifier_compare` can
    # actually give a verdict against. A three-rep run is cheaper and cannot be
    # judged, which is a bad default.
    #
    # A METHOD AND NOT A CONSTANT, because a rake file is loaded before the app
    # is: an app constant in a module body raises `uninitialized constant` at
    # load time, which is why `EvalTasks` above reads `Eval::RunSet::SCORES`
    # inside a method too.
    def default_reps = Eval::Noise::MIN_RUNS

    # A bench run is cents, not dollars -- 300 lines x 4 reps x 2 models is about
    # $0.39 -- so the ceiling is low and the estimate is still printed first: the
    # captain's rule for `eval:run` applies to anything that spends.
    SPEND_CEILING = 0.50

    def reps = (ENV["REPS"].presence || default_reps).to_i

    # THE EXPLICIT ARM SELECTOR, on the captain's instruction of 2026-09-04:
    # `MODELS=` names exactly which models a run measures and the app's rotation
    # is not consulted at all. A bare id is OpenRouter; `ollama:qwen3:8b` names
    # the provider, because an ollama tag has a colon in it.
    #
    #   MODELS=mistralai/mistral-medium-3.1
    #   MODELS=ollama:qwen3:4b,ollama:gemma3:12b
    #   MODELS=ollama:qwen3:4b+nothink            asks a thinking model to stop
    #                                             thinking -- 2.1s a call against
    #                                             100.2s. See Arm::NO_THINKING.
    #
    # `TA_LOCAL_MODELS` is NOT read and not needed: it gates the app's own
    # rotation, and an arm replaces the rotation rather than joining it. The
    # default is still `BaseAgent::REMOTE_MODEL_IDS`, which is what a player
    # gets.
    def arms
      named = ENV["MODELS"].presence&.split(",")&.map(&:strip)

      Eval::Classifier::Arm.all(named.presence || BaseAgent::REMOTE_MODEL_IDS)
    end

    def set_name = ENV["SET"].presence || Time.current.utc.strftime("classifier-%Y%m%d-%H%M%S")

    def available_sets
      found = Dir.glob(Eval.root.join("*", Eval::Classifier::RESULTS)).map { |path| File.basename(File.dirname(path)) }.sort
      found.any? ? "Bench runs: #{found.join(", ")}." : "There are no classifier bench runs yet -- run `rake eval:classifier` first."
    end

    def run!
      corpus = Eval::Classifier.corpus
      problems = corpus.problems
      abort "The corpus does not validate, so nothing measured against it would mean anything:\n  " \
            "#{problems.join("\n  ")}" if problems.any?

      priced = Eval::Classifier.estimate(lines: corpus.size, reps: reps, models: arms)
      calls = corpus.size * reps * arms.size
      puts format("ESTIMATE: %d calls (%d lines x %d reps x %d model%s), about $%.3f. Measured at %d in / %d out a call.",
                  calls, corpus.size, reps, arms.size, arms.one? ? "" : "s", priced,
                  Eval::Classifier::PER_CALL[:input], Eval::Classifier::PER_CALL[:output])
      puts "Local arms (#{arms.select(&:local?).map(&:id).join(", ")}) cost nothing and are not in that figure; " \
           "they are slow instead." if arms.any?(&:local?)
      abort_without_a_key(arms)
      if priced > SPEND_CEILING && ENV["YES"] != "1"
        abort "That is over the $#{format("%.2f", SPEND_CEILING)} this task will spend unattended. " \
              "Re-run with YES=1, or lower REPS."
      end

      puts "Replaying #{corpus.size} lines on #{arms.map(&:id).join(", ")}."
      puts
      result = Eval::Classifier::Bench.new(corpus: corpus, arms: arms, reps: reps).run

      directory = Eval.set_path(set_name)
      written = result.write!(directory, name: set_name)
      puts
      puts "Wrote #{written}."
      puts

      Eval::Classifier::Report.new(result, floor: Eval::Classifier::Offline.new(corpus: corpus).summary)
                              .print(sample: (ENV["SAMPLE"].presence || Eval::Classifier::Report::DEFAULT_SAMPLE).to_i)
      result
    end

    # THE TARGETED PROBE. The two-noun lines alone, which is the whole of what
    # finding F4 is about, at a twentieth of the corpus and a twentieth of the
    # spend. The full bench reports the same figure over every line it already
    # paid for; this is for re-checking it on its own.
    def omission!
      corpus = Eval::Classifier.corpus.two_noun_lines
      puts "#{corpus.size} two-noun lines x #{reps} rep#{"s" unless reps == 1} x #{arms.size} model#{"s" unless arms.one?} " \
           "= #{corpus.size * reps * arms.size} calls, about " \
           "$#{format("%.3f", Eval::Classifier.estimate(lines: corpus.size, reps: reps, models: arms))}."
      abort_without_a_key(arms)
      puts

      result = Eval::Classifier::Bench.new(corpus: corpus, arms: arms, reps: reps).run
      puts
      arms.map(&:id).each do |arm|
        rows = result.for_arm(arm).flat_map { |pass| pass.rows.map { |row| row.transform_keys(&:to_s) } }
        answered = rows.reject { |row| row["error"] }
        omitted = answered.count { |row| row["also_omitted"] }
        found = answered.count { |row| row["also_answered"] }
        puts format("  %-28s %d answers, %d with also_named absent or null (%.3f), %d naming a second thing (%.3f)",
                    arm, answered.size, omitted, answered.empty? ? 0 : omitted.fdiv(answered.size),
                    found, answered.empty? ? 0 : found.fdiv(answered.size))
      end
      puts
      puts "A truly ABSENT field is a failed call -- `BaseAgent#missing_schema_keys` rotates on it -- so"
      puts "an omission shows up as a rotation or a failure and not as a quiet nil. That is the claim"
      puts "this probe checks rather than assumes."
      result
    end

    # A KEY IS ONLY NEEDED FOR A HOSTED ARM. A run of nothing but local models
    # asks the captain's own daemon and needs no key at all, so demanding one
    # would refuse a free measurement.
    def abort_without_a_key(arms)
      if arms.any? { |arm| !arm.local? } && ENV["OPENROUTER_API_KEY"].blank?
        abort "OPENROUTER_API_KEY is not set and #{arms.reject(&:local?).map(&:id).join(", ")} " \
              "#{arms.reject(&:local?).one? ? "is" : "are"} hosted. Name local arms instead " \
              "(MODELS=ollama:qwen3:4b), or run the offline floor, which needs nothing: " \
              "`rake eval:classifier_offline`."
      end
      abort "The bench must not run in the test environment." if Rails.env.test?
    end
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

    def reps = (ENV["REPS"].presence || default_reps).to_i

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
