# A BENCH RUN'S NUMBERS, PERSISTED, so a later prompt change can be judged
# against them.
#
# The same shape as `Eval::RunSet`'s `scores.json` and beside it in the same
# directory: one file per set, written by the run and read by
# `rake eval:classifier_compare`. A classifier set is its OWN file rather than a
# column in the prose set's, because the two measure different things over
# different corpora and a set can legitimately hold one without the other.
#
# WHAT IS KEPT IS EVERY READING, not just the rates. The rates are recomputed
# from them on load, so a change to how a rate is defined does not need the
# calls paid for again -- the same rule `Eval::RunSet` follows by keeping the run
# databases. It is a few hundred kilobytes.
class Eval::Classifier::Result
  # THE FIGURES A COMPARISON JUDGES, one number per pass. Named here rather
  # than derived so that `rake eval:classifier_compare` reports the same four
  # every time and a new one has to be added on purpose.
  #
  # `strict_accuracy` is the headline: the whole answer -- intent and record --
  # over the lines whose English admits one reading. `accuracy` is the same over
  # every line. `refusal_agreement` is what the ruling of 2026-09-04 made
  # load-bearing. `closed_set_misses` is a COUNT rather than a rate, because it
  # is the failure the closed enum exists to prevent and a rate hides how few
  # there should be.
  # SPEED IS ONE OF THEM, on the captain's instruction of 2026-09-04: a model
  # comparison carries a speed verdict beside accuracy, judged by the same
  # `Eval::Noise` rule. `latency_median` is what a turn usually costs the player
  # and `latency_p95` is what the worst turn in twenty costs them -- two figures
  # because on a local model they are not the same number. `failures` is here
  # rather than only on the board because a slow arm and a flaky arm read
  # differently, and a comparison that could not say which had changed would be
  # reporting the wrong thing.
  METRICS = {
    strict_accuracy: "the whole answer right, over unarguable lines",
    accuracy: "the whole answer right, over every line",
    intent_accuracy: "the intent right, whatever it landed on",
    refusal_agreement: "the refusal the line earns, over unarguable lines",
    closed_set_misses: "right intent, wrong record (a count, not a rate)",
    latency_median: "seconds the median call took (CLOCK_MONOTONIC)",
    latency_p95: "seconds the worst call in twenty took",
    failures: "calls that failed outright (a count; the arm has no rotation)"
  }.freeze

  # A FIGURE WHOSE DIRECTION OF IMPROVEMENT IS DOWN. Stated because
  # `Eval::Noise::Verdict#improved?` reads a negative delta as an improvement,
  # which is right for a defect count or a latency and wrong for an accuracy.
  LOWER_IS_BETTER = %i[closed_set_misses latency_median latency_p95 failures].freeze

  # FIGURES THAT ARE COUNTS OR SECONDS RATHER THAN RATES, so a board formats
  # them as what they are.
  COUNTED = %i[closed_set_misses failures].freeze
  SECONDS = %i[latency_median latency_p95].freeze

  attr_reader :corpus_size, :corpus_digest, :arms, :reps, :passes, :warmups, :name, :recorded_at

  def initialize(corpus_size:, arms:, reps:, passes:, warmups: [], corpus_digest: nil,
                 name: nil, recorded_at: nil)
    @corpus_size = corpus_size
    @corpus_digest = corpus_digest
    @arms = arms
    @reps = reps
    @passes = passes
    # NORMALIZED TO STRING KEYS ON THE WAY IN, so one lookup serves a live run
    # and a set loaded off disk -- the same rule `#rows` follows.
    @warmups = Array(warmups).map { |row| (row.respond_to?(:to_h) ? row.to_h : row).transform_keys(&:to_s) }
    @name = name
    @recorded_at = recorded_at
  end

  # WHAT THE FIRST CALL COST THIS ARM, and what the daemon said about keeping a
  # local model in memory. Excluded from every figure in `METRICS`, which are
  # WARM-CACHE FIGURES -- see `Eval::Classifier::Bench`.
  def warmup(arm) = warmups.find { |row| row["arm"].to_s == arm.to_s }

  # WHICH MODELS THIS SET MEASURED, as a set records them. The captain's
  # instruction of 2026-09-04 is that a set has to say which model produced it,
  # so that comparing model A's set against model B's works off the stored file
  # alone -- `arms` is that field and `#answered_by` is the check on it, read
  # back off the readings rather than trusted.
  def models = arms

  # THE MODELS THAT REALLY ANSWERED, out of the rows. Normally the same list;
  # different when the rotation answered a line, which is a fact about the set a
  # later reader has to be able to see.
  def answered_by = rows.map { |row| row["answered_by"] }.compact.uniq.sort

  def self.load(directory)
    dir = Pathname.new(directory)
    file = dir.join(Eval::Classifier::RESULTS)
    unless file.exist?
      raise ArgumentError, "#{file} does not exist -- run the bench on that set first: " \
                           "rake eval:classifier SET=#{dir.basename}"
    end

    document = JSON.parse(File.read(file))
    new(name: document["name"], recorded_at: document["recorded_at"],
        corpus_size: document["corpus_size"], corpus_digest: document["corpus_digest"],
        arms: document.fetch("arms"), reps: document["reps"],
        warmups: document["warmups"].to_a,
        passes: document.fetch("passes").map { |row| Stored.new(row) })
  end

  def write!(directory, name: nil)
    dir = Pathname.new(directory)
    FileUtils.mkdir_p(dir)
    @name ||= name || dir.basename.to_s
    File.write(dir.join(Eval::Classifier::RESULTS), "#{JSON.pretty_generate(to_h)}\n")
    dir.join(Eval::Classifier::RESULTS)
  end

  def for_arm(arm) = passes.select { |pass| pass.arm == arm }

  # EVERY ROW OF EVERY PASS, in the persisted shape. String keys, because that
  # is what a file holds and one code path has to serve both.
  def rows = passes.flat_map { |pass| pass.rows.map { |row| row.transform_keys(&:to_s) } }

  # EVERY PASS'S FIGURE FOR ONE METRIC, which is what `Eval::Noise` compares --
  # one number per repetition, exactly as the prose board hands it one number
  # per run.
  def values(metric, arm: nil)
    scope = arm ? for_arm(arm) : passes
    scope.map { |pass| pass.public_send(metric) }
  end

  def spread(metric, arm: nil) = Eval::Noise.spread(metric, values(metric, arm: arm))

  # EVERY FAILURE THIS ARM HAD, by error class, pooled over its repetitions --
  # the figure that says whether an arm is slow or flaky.
  def failures_by_class(arm)
    for_arm(arm).flat_map { |pass| pass.failures_by_class.to_a }
                .each_with_object({}) { |(klass, count), all| all[klass] = all.fetch(klass, 0) + count }
                .sort_by { |_klass, count| -count }.to_h
  end

  # Whether any arm in this set is one of the captain's own local models. Read
  # by the board, which says so: a local arm costs nothing and is slow, and a
  # figure printed without that beside it invites the wrong comparison.
  def local_arms = arms.select { |arm| Eval::Classifier::Arm.parse(arm).local? }

  def to_h
    { name: name, recorded_at: recorded_at || Time.current.utc.iso8601,
      corpus_size: corpus_size, corpus_digest: corpus_digest, arms: arms, reps: reps,
      answered_by: answered_by, warmups: warmups, passes: passes.map(&:to_h) }
  end

  # A PASS READ BACK OFF DISK. It answers the same questions a live
  # `Eval::Classifier::Bench::Pass` does and holds no `Corpus::Line`, because
  # the corpus may legitimately have moved on since the run -- so a stored pass
  # reports what it measured and never re-derives it against today's labels.
  class Stored
    attr_reader :row

    def initialize(row)
      @row = row
    end

    def arm = row["arm"]
    def rep = row["rep"]
    def readings = rows
    def rows = row["readings"].to_a
    def rotations = row["rotations"].to_i
    def failures = row["failures"].to_i
    def failures_by_class = (row["failures_by_class"] || {}).to_h

    Eval::Classifier::Result::METRICS.each_key do |metric|
      define_method(metric) { row[metric.to_s] }
    end

    def to_h = row

    def by_shape = rows.group_by { |row| row["shape"] }
  end
end
