# A PROMPT BENCH RUN'S NUMBERS, PERSISTED, so a later prompt change can be
# judged against them.
#
# The same convention as `Eval::Classifier::Result` and beside it in the same
# directory: one file per set, written by the run and read by
# `rake eval:prompt_compare` and `rake eval:prompt_board`. Its own file --
# `prompt.json` -- because a set can legitimately hold a prose run, a classifier
# bench and this, and three files of one name cannot.
#
# WHAT IS KEPT IS EVERY READING: the passage, the facts it was scored against,
# the whole prompt that produced it, the tokens and the latency. The rates are
# recomputed from them on load, so a change to how a check reads does not need
# the calls paid for again -- the rule `Eval::RunSet` follows by keeping the run
# databases and `Eval::Classifier::Result` by keeping every reading. It is a
# megabyte or two.
#
# AND A KEPT SET IS A SUMMARY, which is the form that gets checked in. See
# `#summary` for what it gives up and what it keeps.
class Eval::Prompt::Result
  # THE FIGURES A COMPARISON JUDGES, one number per pass. The checks come first
  # and in `Story::Scoreboard::CHECKS` order, because they are what a prompt
  # change is for; the operational figures follow, because a prompt that halved
  # the defect rate and doubled the refusals did not work.
  RUN_METRICS = {
    refusals: "calls the model declined to write (BaseAgent::RefusalError)",
    failures: "calls that failed outright (a count; the arm has no rotation)",
    omitted_fields: "required schema fields that came back absent -- schema'd passes only",
    cap_hits: "fields that arrived at their max_length, so the provider cut them off",
    latency_median: "seconds the median call took (CLOCK_MONOTONIC)",
    latency_p95: "seconds the worst call in twenty took",
    output_tokens: "output tokens over the pass -- what the prose cost to write",
    words: "median words a passage -- length, and NOT a quality figure",
    commitments: "mean rooms, exits, items and people the records know that the prose named"
  }.freeze

  def self.metrics
    @metrics ||= Eval::Prompt.checks.index_with { |code| Story::Scoreboard::CHECKS.fetch(code) }
                                    .merge(RUN_METRICS)
  end

  # A FIGURE WHOSE DIRECTION OF IMPROVEMENT IS DOWN. Every check is a defect
  # rate, and so are the four operational counts.
  def self.lower_is_better
    Eval::Prompt.checks + %i[refusals failures omitted_fields cap_hits latency_median latency_p95]
  end

  # AND THE FIGURES WITH NO BETTER DIRECTION AT ALL, printed with a verdict and
  # no arrow. `Eval::Richness`'s header is the argument: prose that says less
  # cannot contradict the records, so richness is the CHECK ON THE CHECKS and
  # folding it in -- in either direction -- is exactly the mistake it exists to
  # catch. `output_tokens` is the same fact about spend.
  NEUTRAL = %i[words commitments output_tokens].freeze

  COUNTED = %i[refusals failures omitted_fields cap_hits output_tokens words].freeze
  SECONDS = %i[latency_median latency_p95].freeze

  # EVERY FIGURE OF ONE PASS, FROM ITS ROWS -- the one place a figure is
  # computed, so a live run and a set loaded off disk cannot disagree about what
  # a rate means. `Eval::Prompt::Bench::Pass` calls it on the way out and
  # `Stored` reads the answer back off the file.
  def self.figures_of(rows)
    scorer = Eval::Prompt::Scorer.new(rows)
    failed = rows.select { |row| row["error"] }
    latencies = rows.filter_map { |row| row["seconds"] }.sort
    rich = scorer.richness

    { "scanned" => scorer.scanned,
      "cases" => rows.size,
      "failures" => failed.size,
      "refusals" => failed.count { |row| row["error"].to_s.start_with?("BaseAgent::RefusalError") },
      "crises" => failed.count { |row| row["error"].to_s.start_with?("BaseAgent::CrisisResponseError") },
      "rotations" => rows.count { |row| rotated?(row) },
      "extra_calls" => rows.sum { |row| [ row["calls"].to_i - 1, 0 ].max },
      "omitted_fields" => rows.sum { |row| Array(row["missing_fields"]).size },
      "cap_hits" => rows.sum { |row| Array(row["cap_hits"]).size },
      "input_tokens" => rows.sum { |row| row["input_tokens"].to_i },
      "output_tokens" => rows.sum { |row| row["output_tokens"].to_i },
      "latency_median" => Eval.median(latencies),
      "latency_p95" => percentile(latencies),
      "words" => rich.words,
      "commitments" => rich.commitments,
      "coverage" => rich.coverage,
      "chars" => rich.chars,
      "rates" => Eval::Prompt.checks.to_h { |code| [ code.to_s, scorer.rate(code).round(4) ] },
      "flagged" => Eval::Prompt.checks.to_h { |code| [ code.to_s, scorer.flagged_for(code).size ] },
      "judgeable" => Eval::Prompt.checks.to_h { |code| [ code.to_s, scorer.judgeable_for(code) ] },
      "by_story" => rows.group_by { |row| row["story"] }.transform_values(&:size) }
  end

  # Nearest-rank, the same as the classifier bench's: with a few hundred
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

  attr_reader :corpus_size, :corpus_digest, :prompt_digest, :prompt_shapes, :prompt_stable,
              :instructions_digest, :arms, :reps, :passes, :warmups, :name, :recorded_at

  def initialize(corpus_size:, arms:, reps:, passes:, warmups: [], corpus_digest: nil,
                 prompt_digest: nil, prompt_shapes: {}, prompt_stable: true, instructions_digest: nil,
                 instruction_passes: {}, name: nil, recorded_at: nil, answered_by: nil)
    @corpus_size = corpus_size
    @corpus_digest = corpus_digest
    @prompt_digest = prompt_digest
    @prompt_shapes = (prompt_shapes || {}).transform_keys(&:to_s)
    @prompt_stable = prompt_stable
    @instructions_digest = instructions_digest
    @instruction_passes = (instruction_passes || {}).transform_keys(&:to_s)
    @arms = arms
    @reps = reps
    @passes = passes
    @warmups = Array(warmups).map { |row| (row.respond_to?(:to_h) ? row.to_h : row).transform_keys(&:to_s) }
    @name = name
    @recorded_at = recorded_at
    @recorded_answered_by = Array(answered_by).presence
  end

  def models = arms

  # THE INSTRUCTION BLOCK EACH PASS SENT, from the field when the file has it and
  # from the rows when it does not -- the same rule `#answered_by` follows, and
  # it is exact rather than a guess: every row records the digest of the
  # instructions its own call was given. A set written before this field existed
  # still answers, and a SUMMARY set answers from the field because its rows are
  # gone on purpose.
  def instruction_passes
    return @instruction_passes if @instruction_passes.any?

    rows.group_by { |row| row["pass"] }.compact_blank
        .transform_values { |scoped| scoped.filter_map { |row| row["instructions_digest"] }.first }
        .compact.sort.to_h
  end

  def warmup(arm) = warmups.find { |row| row["arm"].to_s == arm.to_s }

  # THE MODELS THAT REALLY ANSWERED, out of the rows -- normally the same list
  # as `arms`, and different only when the pinning failed, which is a fact about
  # the set a later reader has to be able to see.
  def answered_by = @recorded_answered_by || rows.filter_map { |row| row["answered_by"] }.uniq.sort

  def self.load(directory)
    dir = Pathname.new(directory)
    file = dir.join(Eval::Prompt::RESULTS)
    unless file.exist?
      raise ArgumentError, "#{file} does not exist -- run the bench on that set first: " \
                           "rake eval:prompt SET=#{dir.basename}"
    end

    document = JSON.parse(File.read(file))
    new(name: document["name"], recorded_at: document["recorded_at"],
        corpus_size: document["corpus_size"], corpus_digest: document["corpus_digest"],
        prompt_digest: document["prompt_digest"], prompt_shapes: document["prompt_shapes"],
        prompt_stable: document.fetch("prompt_stable", true),
        instructions_digest: document["instructions_digest"],
        instruction_passes: document["instruction_passes"],
        arms: document.fetch("arms"), reps: document["reps"],
        warmups: document["warmups"].to_a, answered_by: document["answered_by"],
        passes: document.fetch("passes").map { |row| Stored.new(row) })
  end

  # THE SAME SET WITH ITS ROWS DROPPED, which is the form that gets checked in.
  #
  # A whole set keeps every passage, every prompt and every fact -- right for
  # `tmp/eval`, where a check can be redefined and rescored without paying for
  # the calls again, and wrong for a file in the repo. A KEPT set holds every
  # pass's figures and no rows: 8 KB against 2 MB, rendering a byte-identical
  # table on `rake eval:prompt_board` and a byte-identical verdict on
  # `rake eval:prompt_compare`.
  #
  # WHAT IT GIVES UP, stated rather than discovered later: the passages
  # themselves, the flagged list with the offending sentence, the prompts, and
  # any figure not already computed. Those live in the run's own output and in
  # the PR body that quoted it.
  def summary
    kept = passes.map { |pass| Stored.new(pass.to_h.transform_keys(&:to_s).merge("readings" => [])) }

    self.class.new(name: name, recorded_at: recorded_at, corpus_size: corpus_size,
                   corpus_digest: corpus_digest, prompt_digest: prompt_digest,
                   prompt_shapes: prompt_shapes, prompt_stable: prompt_stable,
                   instructions_digest: instructions_digest, instruction_passes: instruction_passes,
                   arms: arms, reps: reps, warmups: warmups, answered_by: answered_by, passes: kept)
  end

  def write!(directory, name: nil)
    dir = Pathname.new(directory)
    FileUtils.mkdir_p(dir)
    @name ||= name || dir.basename.to_s
    File.write(dir.join(Eval::Prompt::RESULTS), "#{JSON.pretty_generate(to_h)}\n")
    dir.join(Eval::Prompt::RESULTS)
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
      corpus_size: corpus_size, corpus_digest: corpus_digest,
      prompt_digest: prompt_digest, prompt_shapes: prompt_shapes, prompt_stable: prompt_stable,
      instructions_digest: instructions_digest, instruction_passes: instruction_passes,
      arms: arms, reps: reps, answered_by: answered_by, warmups: warmups,
      passes: passes.map(&:to_h) }
  end

  # A PASS READ BACK OFF DISK. It answers the same questions a live
  # `Eval::Prompt::Bench::Pass` does and holds no `Corpus::Case`: the corpus may
  # legitimately have moved on since the run, so a stored pass reports what it
  # measured and never re-derives it against today's cases.
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
    # existed still answers it, because the facts are stored beside the passage
    # -- which is the whole reason they are stored.
    def figures
      @figures ||= rows.any? ? Eval::Prompt::Result.figures_of(rows) : row
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
