# A REALIZATION BENCH RUN'S NUMBERS, PERSISTED, so a later prompt change can be
# judged against them.
#
# The same convention as `Eval::Prompt::Result` and beside it in the same
# directory: one file per set, written by the run and read by
# `rake eval:realization_compare` and `rake eval:realization_board`. Its own
# file -- `realization.json` -- because a set can legitimately hold a prose run,
# a classifier bench, a prompt bench and this, and four files of one name
# cannot.
#
# WHAT IS KEPT IS EVERY READING: both answers, the facts they were asked
# against, what the registries admitted, the prompts, the tokens and the
# latency. The rates are recomputed from them on load, so a change to how a
# check reads does not need the calls paid for again -- the rule `Eval::RunSet`
# follows by keeping the run databases and `Eval::Prompt::Result` by keeping
# every passage.
#
# AND A KEPT SET IS A SUMMARY, which is the form that gets checked in. See
# `#summary` for what it gives up and what it keeps.
class Eval::Realization::Result
  # THE FIGURES WITH NO BETTER DIRECTION, printed with a verdict and no arrow.
  # `Eval::Realization::Scorer`'s header is the argument, and it is
  # `Eval::Richness`'s applied to rooms: the cheapest way to clear every rate is
  # to write one exit and nobody, so a prompt change that improved every rate
  # and halved these bought its numbers with emptier rooms. Folding them in --
  # in either direction -- is exactly the mistake they exist to catch.
  REPORTED_METRICS = {
    insides_given: "exits given an inside, over exits named -- THE DOMINANT-STRATEGY CHECK on the two " \
                   "inside rates: the cheapest way to clear both is to answer `no inside` every time, and " \
                   "a prompt change that cleared them and halved this bought its numbers with a world of " \
                   "open ground",
    insides_reaching: "exits whose inside pick OPENED a place, over exits named -- `insides_given` cut " \
                      "by what the player got: a pick on a place the world already held is thrown away " \
                      "(`Location::Generator#connect_exit!`), so the distance between the two figures is " \
                      "insides that built nothing. Unavailable on a set stored before the rows recorded " \
                      "what a call opened",
    rooms_laid_out: "mean rooms the layout wrote for a building that was offered the parameters block",
    storeys_below_ground: "mean floors a building was laid out below its ground floor -- the parameter " \
                          "that exists to make \"down\" expressible is worthless if it always comes back none",
    hazard_on_the_ground_floor: "rooms carrying a hazard, on storey 0",
    hazard_below_ground: "the same share below ground -- the captain's own figure, and the ONLY one that " \
                         "reads whether the gradient did anything at all: it is the two ends of the slope, " \
                         "off the rows the layout wrote",
    populations_given: "exits given a population word, over exits named -- `insides_given`'s figure one " \
                       "field over and the same warning: nothing rests on the pick being made " \
                       "(`Location::ExitsSchema`), so a prompt that cleared every rate and halved this " \
                       "handed the words back to the engine",
    crowds_picked: "picks that asked for somebody, over picks made -- THE DOMINANT-STRATEGY CHECK on the " \
                   "population pick: `nobody` is a real answer rather than a default, so a model can make " \
                   "the pick honestly every time and still empty the world, and the two rates would not " \
                   "notice",
    people_named: "mean people one realization wrote",
    people_offered: "mean people the engine ASKED it for -- the denominator, measured and not assumed. " \
                    "Since 2026-09-07 it is an exact count rolled inside the word the narrator picked " \
                    "(`Location::Population`) and not a ceiling, so it moves with the picks: a set either " \
                    "side of that ruling is not comparing the same quantity",
    people_take_up: "people written over slots offered",
    items_named: "mean things one realization put on the floor",
    exits_named: "mean ways out one realization named",
    new_places_opened: "mean places this realization brought into existence -- read off the RECORDS " \
                       "afterwards, so it is what the room really opened",
    new_places_named: "mean names the ANSWER gave that the world did not have -- not the same figure as " \
                      "the one above it: write_exits! stops connecting at the allowance, so a room that " \
                      "named five and was allowed three opened three",
    exits_restating: "exits that named a place the story already had -- the scout's figure, and " \
                     "NOT a defect on its own: the prompt asks for reuse when an exit leads somewhere known"
  }.freeze

  # THE OPERATIONAL FIGURES, which are what says whether a prompt that improved
  # a rate improved anything: a prompt that halved the defects and doubled the
  # refusals did not work.
  RUN_METRICS = {
    refusals: "calls the model declined to answer (BaseAgent::RefusalError)",
    failures: "realizations that failed outright (a count; the arm has no rotation)",
    omitted_fields: "schema fields that came back absent -- top level AND inside a person or a thing",
    cap_hits: "fields that arrived at their max_length, so the provider cut them off",
    latency_median: "seconds the median realization took, both calls (CLOCK_MONOTONIC)",
    latency_p95: "seconds the worst realization in twenty took",
    output_tokens: "output tokens over the pass -- what the rooms cost to write"
  }.freeze

  def self.metrics
    @metrics ||= Eval::Realization::Scorer::CHECKS.dup.merge(REPORTED_METRICS).merge(RUN_METRICS)
  end

  # Defect rates and operational costs have a downward direction. Optional
  # request take-up is reported without calling either direction better.
  def self.lower_is_better
    (Eval::Realization.checks - Eval::Realization::Scorer::OBSERVATIONS) +
      %i[refusals failures omitted_fields cap_hits latency_median latency_p95]
  end

  NEUTRAL = (REPORTED_METRICS.keys + %i[output_tokens] + Eval::Realization::Scorer::OBSERVATIONS).freeze

  COUNTED = %i[refusals failures omitted_fields cap_hits output_tokens].freeze
  SECONDS = %i[latency_median latency_p95].freeze

  # THE FIGURES PRINTED AS A PLAIN MEAN rather than as a rate -- counts of
  # things a room contains, which have no denominator and are not defects.
  MEANS = %i[people_named people_offered items_named exits_named new_places_opened new_places_named
             rooms_laid_out storeys_below_ground].freeze

  # EVERY FIGURE OF ONE PASS, FROM ITS ROWS -- the one place a figure is
  # computed, so a live run and a set loaded off disk cannot disagree about what
  # a rate means. `Eval::Realization::Bench::Pass` calls it on the way out and
  # `Stored` reads the answer back off the file.
  def self.figures_of(rows)
    scorer = Eval::Realization::Scorer.new(rows)
    # THROUGH THE READING AND NOT OFF THE ROW STRING. `Scorer::Reading` owns the
    # one spelling of "was this a refusal" -- the error's CLASS NAME, not a
    # prefix of the stored message, which would count a
    # `BaseAgent::RefusalErrorSomething` as one of them.
    failed = scorer.all_readings.select(&:failed?)
    latencies = rows.filter_map { |row| row["seconds"] }.sort

    { "scanned" => scorer.scanned,
      "cases" => rows.size,
      "failures" => failed.size,
      "refusals" => failed.count(&:refused?),
      "crises" => failed.count(&:crisis?),
      "rotations" => rows.count { |row| rotated?(row) },
      "extra_calls" => scorer.all_readings.sum(&:extra_calls),
      "omitted_fields" => rows.sum { |row| Array(row["missing_fields"]).size },
      "cap_hits" => rows.sum { |row| Array(row["cap_hits"]).size },
      "input_tokens" => rows.sum { |row| row["input_tokens"].to_i },
      "output_tokens" => rows.sum { |row| row["output_tokens"].to_i },
      "latency_median" => Eval.median(latencies),
      "latency_p95" => percentile(latencies),
      "rates" => Eval::Realization.checks.to_h { |code| [ code.to_s, scorer.rate(code).round(4) ] },
      "flagged" => Eval::Realization.checks.to_h { |code| [ code.to_s, scorer.flagged_for(code).size ] },
      "judgeable" => Eval::Realization.checks.to_h { |code| [ code.to_s, scorer.judgeable_for(code) ] },
      "by_story" => rows.group_by { |row| row["story"] }.transform_values(&:size) }.merge(scorer.reported)
  end

  # Nearest-rank, the same as the other two benches': with a few hundred
  # readings the difference from an interpolated percentile is noise, and a
  # percentile that is one of the observed values is one a reader can find.
  def self.percentile(sorted, fraction = 0.95)
    return 0.0 if sorted.empty?

    sorted[[ (sorted.size * fraction).ceil - 1, 0 ].max]
  end

  def self.rotated?(row)
    answered = row["answered_by"]
    return false if answered.blank? || row["arm"].blank?

    answered != Eval::Classifier::Arm.parse(row["arm"]).model
  end

  attr_reader :request_identity, :corpus_size, :corpus_digest, :prompt_digest, :prompt_shapes, :prompt_stable,
              :instructions_digest, :arms, :reps, :passes, :warmups, :name, :recorded_at

  def initialize(corpus_size:, arms:, reps:, passes:, warmups: [], corpus_digest: nil, request_identity: nil,
                 prompt_digest: nil, prompt_shapes: {}, prompt_stable: true, instructions_digest: nil,
                 name: nil, recorded_at: nil, answered_by: nil)
    @corpus_size = corpus_size
    @corpus_digest = corpus_digest
    @request_identity = request_identity&.deep_stringify_keys
    @prompt_digest = prompt_digest
    @prompt_shapes = (prompt_shapes || {}).transform_keys(&:to_s)
    @prompt_stable = prompt_stable
    @instructions_digest = instructions_digest
    @arms = arms
    @reps = reps
    @passes = passes
    @warmups = Array(warmups).map { |row| (row.respond_to?(:to_h) ? row.to_h : row).transform_keys(&:to_s) }
    @name = name
    @recorded_at = recorded_at
    @recorded_answered_by = Array(answered_by).presence
  end

  def models = arms

  def warmup(arm) = warmups.find { |row| row["arm"].to_s == arm.to_s }

  # THE MODELS THAT REALLY ANSWERED, out of the rows -- normally the same list
  # as `arms`, and different only when the pinning failed, which is a fact about
  # the set a later reader has to be able to see.
  def answered_by = @recorded_answered_by || rows.filter_map { |row| row["answered_by"] }.uniq.sort

  def self.load(directory)
    dir = Pathname.new(directory)
    file = dir.join(Eval::Realization::RESULTS)
    unless file.exist?
      raise ArgumentError, "#{file} does not exist -- run the bench on that set first: " \
                           "rake eval:realization SET=#{dir.basename}"
    end

    document = JSON.parse(File.read(file))
    new(name: document["name"], recorded_at: document["recorded_at"],
        corpus_size: document["corpus_size"], corpus_digest: document["corpus_digest"], request_identity: document["request_identity"],
        prompt_digest: document["prompt_digest"], prompt_shapes: document["prompt_shapes"],
        prompt_stable: document.fetch("prompt_stable", true),
        instructions_digest: document["instructions_digest"],
        arms: document.fetch("arms"), reps: document["reps"],
        warmups: document["warmups"].to_a, answered_by: document["answered_by"],
        passes: document.fetch("passes").map { |row| Stored.new(row) })
  end

  # THE SAME SET WITH ITS ROWS DROPPED, which is the form that gets checked in.
  #
  # A whole set keeps every answer, every prompt and every fact -- right for
  # `tmp/eval`, where a check can be redefined and rescored without paying for
  # the calls again, and wrong for a file in the repo. A KEPT set holds every
  # pass's figures and no rows, rendering a byte-identical table on
  # `rake eval:realization_board` and a byte-identical verdict on
  # `rake eval:realization_compare`.
  #
  # WHAT IT GIVES UP, stated rather than discovered later: the rooms themselves,
  # the flagged list with the offending name, the prompts, and any figure not
  # already computed. Those live in the run's own output and in the PR body that
  # quoted it.
  def summary
    # THE FIGURES AND NOT THE ROW, so a summary of a summary is the same
    # summary: `Stored#figures` computes from the readings where there are any
    # and reads them off the field where there are not, and taking the row would
    # keep whichever of the two the pass happened to be built from.
    kept = passes.map { |pass|
      Stored.new(pass.figures.merge("arm" => pass.arm, "rep" => pass.rep, "readings" => []))
    }

    self.class.new(name: name, recorded_at: recorded_at, corpus_size: corpus_size,
                   corpus_digest: corpus_digest, request_identity: request_identity, prompt_digest: prompt_digest,
                   prompt_shapes: prompt_shapes, prompt_stable: prompt_stable,
                   instructions_digest: instructions_digest, arms: arms, reps: reps,
                   warmups: warmups, answered_by: answered_by, passes: kept)
  end

  def write!(directory, name: nil)
    dir = Pathname.new(directory)
    FileUtils.mkdir_p(dir)
    @name ||= name || dir.basename.to_s
    File.write(dir.join(Eval::Realization::RESULTS), "#{JSON.pretty_generate(to_h)}\n")
    dir.join(Eval::Realization::RESULTS)
  end

  def for_arm(arm) = passes.select { |pass| pass.arm == arm }

  def rows = passes.flat_map { |pass| pass.rows.map { |row| row.transform_keys(&:to_s) } }

  # EVERY PASS'S FIGURE FOR ONE METRIC -- one number per repetition, which is
  # exactly what `Eval::Noise` compares.
  def values(metric, arm: nil)
    scope = arm ? for_arm(arm) : passes
    scope.map { |pass| pass.figure(metric) }
  end

  def spread(metric, arm: nil) = Eval::Noise.spread(metric, values(metric, arm: arm))

  def failures_by_class(arm)
    for_arm(arm).flat_map(&:rows).filter_map { |row| row["error"]&.split(": ")&.first }
                .tally.sort_by { |_klass, count| -count }.to_h
  end

  def to_h
    { name: name, recorded_at: recorded_at || Time.current.utc.iso8601,
      corpus_size: corpus_size, corpus_digest: corpus_digest, request_identity: request_identity,
      prompt_digest: prompt_digest, prompt_shapes: prompt_shapes, prompt_stable: prompt_stable,
      instructions_digest: instructions_digest,
      arms: arms, reps: reps, answered_by: answered_by, warmups: warmups,
      passes: passes.map(&:to_h) }
  end

  # A PASS READ BACK OFF DISK. It answers the same questions a live
  # `Eval::Realization::Bench::Pass` does and holds no `Corpus::Case`: the
  # corpus may legitimately have moved on since the run, so a stored pass
  # reports what it measured and never re-derives it against today's cases.
  #
  # THE FIGURES COME FROM THE FIELD WHEN THE FIELD IS THERE AND FROM THE ROWS
  # WHEN IT IS NOT, which is what lets a SUMMARY set -- rows dropped on purpose
  # so it can be checked in -- print the same table as the whole run it came
  # from, and lets a whole set be rescored after a check is redefined.
  class Stored
    attr_reader :row

    def initialize(row)
      @row = row
    end

    def arm = row["arm"]
    def rep = row["rep"]
    def rows = row["readings"].to_a
    def readings = rows

    # RESCORED FROM THE ROWS WHERE THERE ARE ROWS. A set written before a check
    # existed still answers it, because the facts are stored beside the answer
    # -- which is the whole reason they are stored.
    def figures
      @figures ||= rows.any? ? Eval::Realization::Result.figures_of(rows) : row
    end

    def figure(metric)
      name = metric.to_s
      return figures["rates"][name] if figures["rates"].is_a?(Hash) && figures["rates"].key?(name)

      figures[name]
    end

    def rates = figures["rates"] || {}
    def flagged = figures["flagged"] || {}
    def judgeable = figures["judgeable"] || {}
    def scanned = figures["scanned"].to_i
    def failures = figures["failures"].to_i
    def rotations = figures["rotations"].to_i
    def extra_calls = figures["extra_calls"].to_i
    def input_tokens = figures["input_tokens"].to_i
    def output_tokens = figures["output_tokens"].to_i

    def to_h = row
  end
end
