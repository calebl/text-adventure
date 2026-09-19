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

  # ADDED BESIDE `METRICS` RATHER THAN INSIDE IT, ON PURPOSE.
  # `PhysicalClassifierStudy::Audit` (`db/eval/physical-classifier-20260910/audit.rb`,
  # a frozen snapshot never edited in place) iterates `METRICS.each_key` and
  # `.fetch`es every one off a kept JSON summary captured before this counter
  # existed -- putting `out_of_set` inside `METRICS` would raise a `KeyError`
  # there on a baseline that can never grow the field. `out_of_set` is measured
  # and compared exactly like the eight above -- see
  # `Eval::Classifier::Bench::Reading#out_of_set?` for what it counts and why it
  # is not `closed_set_misses` -- it is just never asked of a baseline older
  # than it.
  ADDITIONAL_METRICS = {
    out_of_set: "a target or also_named named on no list at all (a count, not a rate)"
  }.freeze

  # WHAT A LIVE REPORT PRINTS AND `rake eval:classifier_compare` JUDGES.
  # `METRICS` alone is what a frozen historical replay may still assume.
  COMPARABLE_METRICS = METRICS.merge(ADDITIONAL_METRICS).freeze

  # A FIGURE WHOSE DIRECTION OF IMPROVEMENT IS DOWN. Stated because
  # `Eval::Noise::Verdict#improved?` reads a negative delta as an improvement,
  # which is right for a defect count or a latency and wrong for an accuracy.
  LOWER_IS_BETTER = %i[closed_set_misses out_of_set latency_median latency_p95 failures].freeze

  # FIGURES THAT ARE COUNTS OR SECONDS RATHER THAN RATES, so a board formats
  # them as what they are.
  COUNTED = %i[closed_set_misses out_of_set failures].freeze
  SECONDS = %i[latency_median latency_p95].freeze

  # HOW MANY CALLS OF ONE ARM WERE IN FLIGHT WHEN THIS SET WAS TAKEN, and the
  # figure a set written before concurrency existed reads as. A serial set is 1
  # and every checked-in baseline under `db/eval` is one of those -- taken
  # before `Eval::Concurrency`, and deliberately not regenerated.
  #
  # IT IS RECORDED BECAUSE IT MOVES TWO OF THE EIGHT `METRICS` AND NOTHING ELSE.
  # `latency_median` and `latency_p95` are wall clocks, and past the provider's
  # own ceiling a wall clock is queueing time: +4% at eight in flight, +20% at
  # sixteen, +169% at thirty-two. The accuracies, the closed-set misses and the
  # refusal agreement are unaffected -- measured identical, sequential against
  # N=8, on the same lines and positions. So a comparison across two different
  # concurrencies is a real comparison of six figures and a manufactured one of
  # two, and `Eval::Classifier::Comparison` suppresses exactly those two.
  SERIAL = 1

  attr_reader :request_identity, :corpus_size, :corpus_digest, :arms, :reps, :passes, :warmups, :name, :recorded_at, :concurrency, :cascade

  # `cascade` IS PROVENANCE, NOT A METRIC: whether this set was taken with
  # `Eval::Classifier::Bench.new(cascade: true)`, so the READER measured was
  # `Playthrough::Classifier::Cascade` in front of the arm rather than the arm
  # alone. The arm named is unchanged either way -- the cascade's escalation
  # target -- which is what lets `rake eval:classifier_compare` pair a cascade
  # set against the kept Mistral-alone set with no separate provider entry:
  # both record the same arm, and this flag is the only thing that tells them
  # apart. See `Eval::Classifier::Bench#initialize`.
  def initialize(corpus_size:, arms:, reps:, passes:, warmups: [], corpus_digest: nil, request_identity: nil,
                 name: nil, recorded_at: nil, answered_by: nil, concurrency: SERIAL, cascade: false)
    @corpus_size = corpus_size
    @corpus_digest = corpus_digest
    @request_identity = request_identity&.deep_stringify_keys
    @arms = arms
    @reps = reps
    @concurrency = (concurrency || SERIAL).to_i
    @cascade = !!cascade
    @passes = passes
    # NORMALIZED TO STRING KEYS ON THE WAY IN, so one lookup serves a live run
    # and a set loaded off disk -- the same rule `#rows` follows.
    @warmups = Array(warmups).map { |row| (row.respond_to?(:to_h) ? row.to_h : row).transform_keys(&:to_s) }
    @name = name
    @recorded_at = recorded_at
    # RECORDED RATHER THAN DERIVED WHEN THE FILE HAS IT, because a summary set
    # has no rows to derive it from and "which model really answered" is
    # provenance a kept file must not lose.
    @recorded_answered_by = Array(answered_by).presence
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
  def answered_by = @recorded_answered_by || rows.map { |row| row["answered_by"] }.compact.uniq.sort

  def self.load(directory)
    dir = Pathname.new(directory)
    file = dir.join(Eval::Classifier::RESULTS)
    unless file.exist?
      raise ArgumentError, "#{file} does not exist -- run the bench on that set first: " \
                           "rake eval:classifier SET=#{dir.basename}"
    end

    document = JSON.parse(File.read(file))
    new(name: document["name"], recorded_at: document["recorded_at"],
        corpus_size: document["corpus_size"], corpus_digest: document["corpus_digest"], request_identity: document["request_identity"],
        arms: document.fetch("arms"), reps: document["reps"],
        concurrency: document["concurrency"] || SERIAL, cascade: document["cascade"] || false,
        warmups: document["warmups"].to_a, answered_by: document["answered_by"],
        passes: document.fetch("passes").map { |row| Stored.new(row) })
  end

  # THE SAME SET WITH ITS ROWS DROPPED, which is the form that gets checked in.
  #
  # A whole set is 1.1 MB a model because it keeps every reading, and that is
  # right for `tmp/eval`: a rate can be redefined and recomputed without paying
  # for the calls again. It is wrong for a file in the repo. So a KEPT set holds
  # every pass's figures plus `#also_counts`, and `Stored` reads those from the
  # field instead of counting rows -- enough for `rake eval:classifier_board`
  # and `rake eval:classifier_compare` to run exactly as they do on a whole set.
  #
  # WHAT IT GIVES UP, stated rather than discovered later: the MISSED list, the
  # per-shape and per-intent breakdowns, and any figure not already computed --
  # everything that needs to know what a particular line came back as. Those
  # live in the run's own output and in the PR body that quoted it.
  #
  # `keep_rows:` IS THE ONE ESCAPE HATCH, and it exists for exactly one reason:
  # a cascade set cannot be reconciled line by line from four aggregate numbers
  # a side. `Eval::Classifier::Bench::Reading` carries the two Noul readings
  # (`target_present`, `named_more_than_one`) beside the typed line, the
  # expected answer and the answer used -- everything a later diagnosis needs
  # to find which lines a composition rule got wrong -- and dropping them here
  # the way every non-cascade kept set does would throw that away with no way
  # to get it back short of paying for the calls again.
  def summary(keep_rows: false)
    kept = passes.map do |pass|
      # The counts are computed BEFORE the rows go, or they could never be
      # computed again -- which is the one way this conversion could quietly
      # produce a file that renders a wrong table.
      rows = keep_rows ? pass.rows.map { |reading_row| reading_row.transform_keys(&:to_s) } : []
      row = pass.to_h.transform_keys(&:to_s)
                .merge(pass.also_counts.transform_keys(&:to_s), "readings" => rows)
      Stored.new(row)
    end

    self.class.new(name: name, recorded_at: recorded_at, corpus_size: corpus_size,
                   corpus_digest: corpus_digest, request_identity: request_identity, arms: arms, reps: reps, warmups: warmups,
                   answered_by: answered_by, concurrency: concurrency, cascade: cascade, passes: kept)
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
      corpus_size: corpus_size, corpus_digest: corpus_digest, request_identity: request_identity, arms: arms, reps: reps,
      concurrency: concurrency, cascade: cascade, answered_by: answered_by, warmups: warmups,
      passes: passes.map(&:to_h) }
  end

  # ESCALATION, FALL-THROUGH AND KEY-PRESENT SHARE, POOLED ACROSS THIS ARM'S
  # REPETITIONS -- the figures `scenes.resolved_by` makes visible in production,
  # read here off the same column's bench-side counterpart
  # (`Eval::Classifier::Bench::Pass#resolved_by_counts`). Empty on a set that
  # pinned the reader off, which is every set before this one existed.
  def resolved_by_counts(arm)
    for_arm(arm).each_with_object(Hash.new(0)) do |pass, all|
      pass.resolved_by_counts.each { |path, count| all[path] += count }
    end
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
    def resolved_by_counts = (row["resolved_by_counts"] || {}).to_h

    Eval::Classifier::Result::METRICS.each_key do |metric|
      define_method(metric) { row[metric.to_s] }
    end

    # `ADDITIONAL_METRICS` READ SEPARATELY, so a row written before
    # `out_of_set` existed answers `nil` -- "not recorded" on the board -- and
    # not a `KeyError` or a false zero.
    Eval::Classifier::Result::ADDITIONAL_METRICS.each_key do |metric|
      define_method(metric) { row[metric.to_s] }
    end

    def to_h = row

    def by_shape = rows.group_by { |row| row["shape"] }

    # THE DETECTOR COUNTS, FROM THE FIELD IF IT IS THERE AND FROM THE ROWS IF IT
    # IS NOT. A set written before these were recorded still answers correctly,
    # by counting -- and a SUMMARY set, whose rows were dropped on purpose to be
    # checked in, answers from the field. Neither reader has to know which kind
    # of file it is holding.
    def also_counts
      return COUNTS.index_with { |key| row[key.to_s].to_i } if row.key?("also_tp")

      { also_tp: rows.count { |r| r["also_tp"] }, also_fp: rows.count { |r| r["also_fp"] },
        also_fn: rows.count { |r| r["also_fn"] },
        also_omitted: rows.count { |r| r["also_omitted"] },
        answered: rows.count { |r| r["error"].nil? }, readings_count: rows.size }
    end

    COUNTS = %i[also_tp also_fp also_fn also_omitted answered readings_count].freeze
  end
end
