# THE CORPUS, REPLAYED THROUGH THE REAL CLASSIFIER.
#
# One `Playthrough::Classifier#classify` per line per repetition per model, and
# nothing stubbed on the way: the same closed enum, the same prompt, the same
# `BaseAgent`, against a position whose closed sets are exactly the ones the
# label was written against. What comes back is compared to the label and the
# comparison is `Eval::Classifier::Reading`.
#
# SEVERAL REPETITIONS, BECAUSE ONE IS NOT A MEASUREMENT. The classifier runs at
# `TEMPERATURE = 0.0` and a provider is still not deterministic -- the same line
# in the same room does not always come back the same way, which is the whole
# reason `EVALUATION.md` reports a band. So a bench run is REPS passes and the
# board prints min, median and max across them; `rake eval:classifier_compare`
# judges a later prompt change against that band with the same exact rank test
# `Eval::Noise` gives the prose loop.
#
# PER MODEL, AND ONE MODEL PER ARM WITH NOTHING BEHIND IT. An arm is an
# `Eval::Classifier::Arm` -- a provider and a model named explicitly, hosted or
# local -- and `Arm#pinned` replaces `BaseAgent.default_model_options` for the
# length of one pass. So the rotation is off by construction and a failed call
# is a failed line attributed to the model that failed it; read that class's
# header for the three reasons that is what a measurement wants. `#rotated?`
# survives as a guard rather than a figure: it reads the model that ACTUALLY
# answered off `BaseAgent#current_model`, and if it is ever anything but the arm
# the board says so instead of quietly crediting the wrong model.
#
# AND SPEED IS A MEASURED FACTOR, on the captain's instruction of 2026-09-04.
# Every call is timed on `CLOCK_MONOTONIC` -- monotonic rather than wall clock
# because a wall clock can step backwards under NTP and a negative latency is a
# figure nobody can read -- and the board prints the median and the p95 per
# model with a band across repetitions, exactly as it prints the accuracies. The
# median is what a turn usually costs the player; the p95 is what the worst turn
# in twenty costs them, which on a local model is a different number entirely.
# A LATENCY IS ONLY MEANINGFUL WITH THE FAILURES BESIDE IT: a slow arm and a
# flaky arm read differently, and an arm that failed a third of its calls has a
# median measured over the two thirds that answered.
#
# AND THE FIRST CALL IS ITS OWN FIGURE, on the captain's follow-up of
# 2026-09-04. A local model pays a load cost of seconds to tens of seconds on
# the first call, and ollama unloads it again after about five minutes idle --
# so a run that folded that into the median would report the model-load time as
# the model's speed. Every arm therefore gets ONE WARM CALL before its first
# pass, timed and reported as `cold_start`, excluded from the pass entirely. The
# figures the board prints are WARM-CACHE FIGURES and say so.
#
# For a hosted arm the same warm call makes the first-call outlier -- connection
# setup, a cold route -- visible as its own number rather than hidden in the
# band, which is what the follow-up asked for on that side.
#
# THE ARM'S REPETITIONS RUN CONTIGUOUSLY and models are never interleaved: the
# loop is arms outside, reps inside, so a local model is asked 300 questions
# four times over without another model being loaded in between. On top of that
# `Arm#keep_resident!` pins it for 45 minutes through the daemon's own API --
# out of band, so the app's calls stay ordinary calls. Whether that took is
# reported.
#
# ONE MODEL CALL PER LINE AND NOT ONE MORE. The positions are staged offline
# (`Eval::Classifier::Stage`), the whole run is inside a rolled-back
# transaction, and nothing here narrates, generates a room or writes a Scene.
# The `Playthrough::Drift` and `Playthrough::Overreach` rows `#classify` writes
# are written and rolled back with everything else.
class Eval::Classifier::Bench
  # WHAT ONE LINE CAME BACK AS, next to what it should have been.
  #
  # `action`, `target` and `also_named` are the classifier's answer as NAMES --
  # `Playthrough::Classifier.label_for` of the records it resolved -- because
  # the corpus holds names and a record cannot be compared to one directly.
  # `answered_by` is the model that really answered.
  #
  # `raw` is THE PROVIDER'S OWN JSON, read back off `messages.content_raw` --
  # the column PR 97 stopped pruning. It is here for one reason: PR 102's review
  # finding F4 worried that `also_named`, a REQUIRED field on the commonest
  # model call in the app, would come back missing or null, and neither the
  # resolved `Intent` nor a rate over it can tell an omitted field from an
  # answer of `nothing`. `Eval::Classifier::Omission` reads it and the board
  # prints the figure. See `BaseAgent#missing_schema_keys`, which fails the call
  # when a field is truly absent -- so an omission shows up as a rotation or a
  # failure and NOT as a quiet nil, and this is how that claim is checked
  # rather than assumed.
  # `seconds` is the wall clock of the one call, `CLOCK_MONOTONIC`, including
  # the schema build and the resolution back to records -- which is what a turn
  # actually waits for, and both are microseconds beside a provider round trip.
  Reading = Data.define(:line, :arm, :rep, :answer, :answered_by, :raw, :seconds, :error) do
    def id = line.id
    def shape = line.shape
    def arguable? = line.arguable?
    def failed? = !error.nil?

    def intent = answer&.intent
    def refusal = answer&.refusal

    # RIGHT INTENT, whatever it landed on. Kept apart from the target because
    # they are different failures with different consequences: a wrong intent
    # sends the turn down another branch, a wrong target sends the right branch
    # at the wrong record.
    def intent_right? = !failed? && line.answers.any? { |wanted| wanted.intent == answer.intent }

    # RIGHT INTENT AND RIGHT RECORD -- the whole answer. The pair is compared as
    # a set; see `Eval::Classifier::Corpus::Answer`.
    def right? = !failed? && line.accepts?(answer)

    # THE CLOSED-SET MISS: the branch was right and the record was not. This is
    # the failure the closed enum was built to make impossible and the one worth
    # counting on its own -- it means the model named something in the set that
    # is not what the line named, or named `nothing` where a record was there.
    def closed_set_miss? = intent_right? && !right?

    def refusal_right? = !failed? && line.refusals.include?(answer.refusal)

    # THE GUARD, not a figure. With an arm of one there is nothing to rotate to,
    # so this is false on every reading of a healthy run -- and if it is ever
    # true the pinning failed and the board must not credit this arm.
    #
    # COMPARED AS A MODEL AND NOT AS A LABEL. `arm` is the arm's id, which
    # carries the provider for a local model and `+nothink` for an arm that
    # asked, while `answered_by` is what `BaseAgent#current_model` says -- the
    # bare model. Compared as strings, every local reading would have read as a
    # rotation and the board would have refused to credit a healthy run; it did,
    # on the first local pass. `Arm#id` round-trips through `Arm.parse`, which is
    # what makes this the model the arm named.
    def rotated?
      return false if answered_by.nil?

      answered_by != Eval::Classifier::Arm.parse(arm).model
    end

    # WHY A CALL FAILED, as a class name. A local model that will not honour a
    # schema fails differently from a provider that timed out, and a count
    # cannot tell them apart.
    #
    # Split on COLON-SPACE and not on a colon: `#read` writes
    # `"#{error.class}: #{error.message}"` and the class is usually namespaced,
    # so a bare colon turns `BaseAgent::SchemaIgnoredError` into `BaseAgent`.
    def error_class = error&.split(": ")&.first

    # --- `also_named` as a detector, which is what precision and recall are of.
    # A POSITIVE is a line whose LABEL carries a second name; that is the corpus
    # saying this line asked for two acts. See `Eval::Classifier::Report`.
    def also_expected? = !line.also_named.nil?
    def also_answered? = !failed? && !answer.also_named.nil?
    def also_true_positive? = also_expected? && also_answered? && right?
    def also_false_positive? = !failed? && !also_expected? && also_answered?
    def also_false_negative? = also_expected? && !also_true_positive?

    # WHETHER THE PROVIDER SENT THE REQUIRED FIELD AT ALL, told apart from
    # sending it as `nothing`. `nil` means the run predates the raw answer being
    # kept, and is not counted either way.
    def also_named_field
      return nil if raw.nil?

      raw.key?("also_named") ? raw["also_named"] : :missing
    end

    def also_named_omitted? = [ :missing, nil, "" ].include?(also_named_field) && !raw.nil?
  end

  # WHAT THE FIRST CALL COST, once per arm. `residency` is what the daemon said
  # about keeping a local model in memory: `:resident`, `:refused`,
  # `:unreachable`, or `:not_local` for a hosted arm.
  Warmup = Data.define(:arm, :seconds, :residency, :error) do
    def failed? = !error.nil?
    def to_h = { arm:, seconds: seconds&.round(4), residency: residency.to_s, error: }
  end

  # ONE PASS OF THE WHOLE CORPUS ON ONE MODEL.
  Pass = Data.define(:arm, :rep, :readings) do
    def scored = readings.reject(&:failed?)

    # A COUNT, not the rows -- `#failed` is the rows. They were one method and
    # the board summed it, which is how `Array can't be coerced into Integer`
    # happens on a line nobody reads twice. `Eval::Classifier::Result::Stored`
    # reads the same name back off disk as a number, so this is the shape both
    # sides have to agree on.
    def failed = readings.select(&:failed?)
    def failures = failed.size
    def rotations = readings.count(&:rotated?)

    # --- speed. Over the readings that ANSWERED, because a failed call has no
    # latency to report -- and the failure count beside it is what says how much
    # of the arm the figure covers.
    def latencies = scored.map(&:seconds).compact.sort

    def latency_median = Eval.median(latencies)

    # THE WORST TURN IN TWENTY. Nearest-rank rather than interpolated: with a
    # few hundred readings the difference is noise, and a percentile that is one
    # of the observed values is one a reader can go and find in the rows.
    def latency_p95
      return 0.0 if latencies.empty?

      latencies[[ (latencies.size * 0.95).ceil - 1, 0 ].max]
    end

    def failures_by_class = failed.map(&:error_class).tally.sort_by { |_klass, count| -count }.to_h

    def accuracy = rate(scored.count(&:right?), scored.size)
    def intent_accuracy = rate(scored.count(&:intent_right?), scored.size)

    # THE HEADLINE IS TAKEN OVER THE UNARGUABLE LINES, because a line with an
    # `also_accept` is a line the corpus admits two readings of, and a rate that
    # pooled them would be reporting the labelling. Both are printed.
    def unarguable = scored.reject(&:arguable?)
    def strict_accuracy = rate(unarguable.count(&:right?), unarguable.size)

    def refusal_agreement = rate(unarguable.count(&:refusal_right?), unarguable.size)
    def closed_set_misses = scored.count(&:closed_set_miss?)

    def rate(part, whole) = whole.zero? ? 0.0 : part.fdiv(whole)

    # ONE ROW PER LINE, AS THE PERSISTED FILE HOLDS IT. `Eval::Classifier::Report`
    # reads these and never the `Reading` objects, so one code path prints a live
    # run and a set loaded off disk -- see `Eval::Classifier::Result::Stored`.
    def rows = readings.map { |reading| reading_h(reading) }

    # THE `also_named` DETECTOR AS FOUR NUMBERS, so a pass can answer for itself
    # without carrying its rows. `Eval::Classifier::Board` needs exactly these
    # and the answered count; every other figure it prints is already a number
    # on the pass. That is what makes a SUMMARY set -- one with `readings: []` --
    # enough for `rake eval:classifier_board` and `rake eval:classifier_compare`,
    # which is what the checked-in baseline is. See `Result#summary`.
    def also_counts
      { also_tp: scored.count(&:also_true_positive?), also_fp: scored.count(&:also_false_positive?),
        also_fn: scored.count(&:also_false_negative?),
        also_omitted: scored.count(&:also_named_omitted?), answered: scored.size,
        readings_count: readings.size }
    end

    def to_h = { arm:, rep:, accuracy: accuracy.round(4), intent_accuracy: intent_accuracy.round(4),
                 strict_accuracy: strict_accuracy.round(4), refusal_agreement: refusal_agreement.round(4),
                 closed_set_misses:, latency_median: latency_median.round(4),
                 latency_p95: latency_p95.round(4), failures:,
                 rotations:, failures_by_class: failures_by_class,
                 **also_counts, readings: rows }

    def reading_h(reading)
      line = reading.line
      { id: reading.id, shape: reading.shape, typed: line.typed, position: line.position,
        expected: line.answers.map(&:to_s), got: reading.answer&.to_s,
        expected_intent: line.intent, got_intent: reading.intent,
        expected_refusals: line.refusals, got_refusal: reading.refusal,
        right: reading.right?, intent_right: reading.intent_right?,
        closed_set_miss: reading.closed_set_miss?,
        refusal_right: reading.refusal_right?, arguable: reading.arguable?,
        also_expected: reading.also_expected?, also_answered: reading.also_answered?,
        also_tp: reading.also_true_positive?, also_fp: reading.also_false_positive?,
        also_fn: reading.also_false_negative?, also_omitted: reading.also_named_omitted?,
        answered_by: reading.answered_by, seconds: reading.seconds&.round(4), error: reading.error }
    end
  end

  attr_reader :corpus, :arms, :reps, :io

  # `reps` defaults to `Eval::Noise::MIN_RUNS` and not to a number of its own,
  # for the reason the rake task states: a run taken at the default has to be a
  # run a later comparison can give a verdict against. Two defaults that
  # disagreed would put an unjudgeable set on disk.
  def initialize(corpus: Eval::Classifier.corpus, arms: nil, reps: Eval::Noise::MIN_RUNS, io: $stdout)
    @corpus = corpus
    @arms = Eval::Classifier::Arm.all(arms.presence || BaseAgent::REMOTE_MODEL_IDS)
    @reps = reps
    @io = io
  end

  # Returns an `Eval::Classifier::Result`. A line whose call failed after the
  # rotation is recorded as a failure and the pass keeps going, because a
  # provider dropping one call in three hundred must not cost the whole run.
  #
  # ONE TRANSACTION PER PASS AND NOT ONE FOR THE RUN, which is a fact about
  # SQLite rather than about isolation. A whole run is a few thousand calls and
  # the better part of an hour; one open write transaction across that locks the
  # development database for its whole length, and `rake game:sweep` or a
  # browser turn in the next terminal fails with `database is locked`. Per pass
  # it is a few minutes, and the eighty-odd extra seed loads cost seconds
  # offline.
  #
  # It is also the better isolation: the `Playthrough::Drift` and
  # `Playthrough::Overreach` rows a pass writes do not accumulate underneath the
  # next one.
  def run
    passes = []
    warmups = []

    arms.each do |arm|
      arm.pinned do
        warmups << warm(arm)
        (1..reps).each do |rep|
          Eval::Classifier::Stage.open(corpus.positions) { |stages| passes << play(arm, rep, stages) }
        end
      end
    end

    Eval::Classifier::Result.new(corpus_size: corpus.size, corpus_digest: Eval::Classifier.digest(corpus),
                                 arms: arms.map(&:id), reps: reps, passes: passes, warmups: warmups)
  end

  private

  # ONE CALL BEFORE THE MEASUREMENT, TIMED AND THEN SET ASIDE. It is a real
  # classifier call on a real position, because a warm-up that took a different
  # path would warm a different thing -- and its duration is the cold start,
  # which for a local model is mostly the model being read off disk into memory.
  #
  # The residency request comes AFTER it rather than before, deliberately: ask
  # the daemon to load the model first and the cold start would measure nothing.
  def warm(arm)
    line = corpus.lines.first
    seconds = nil
    error = nil

    Eval::Classifier::Stage.open([ corpus.position(line.position) ]) do |stages|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      reading = read(line, stages.fetch(line.position), arm, 0)
      seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      error = reading.error
    end

    residency = arm.keep_resident!
    warmup = Warmup.new(arm: arm.id, seconds: seconds, residency: residency, error: error)
    io&.puts format("  %-22s first call %.1fs%s%s", arm.id, seconds,
                    arm.local? ? " (model load), kept resident: #{residency}" : " (excluded from the figures below)",
                    error ? " -- FAILED: #{error}" : "")
    warmup
  end

  def play(arm, rep, stages)
    io&.print format("  %-22s rep %d ", arm.id, rep)
    readings = corpus.lines.map { |line| read(line, stages.fetch(line.position), arm, rep) }
    pass = Pass.new(arm: arm.id, rep: rep, readings: readings)
    io&.puts format("%3d/%-3d right (%.3f), %2d misses, %.2fs median / %.2fs p95%s%s",
                    pass.scored.count(&:right?), pass.scored.size, pass.accuracy, pass.closed_set_misses,
                    pass.latency_median, pass.latency_p95,
                    pass.failures.positive? ? ", #{pass.failures} FAILED (#{pass.failures_by_class.keys.first})" : "",
                    pass.rotations.positive? ? ", #{pass.rotations} ROTATED -- THE PINNING FAILED" : "")
    pass
  end

  # ONE LINE. A fresh `Playthrough::Classifier` per line, because the agent it
  # memoizes is one conversation and the classifier is stateless by design --
  # "there is nothing in last turn's exchange worth replaying".
  def read(line, standing, arm, rep)
    classifier = Playthrough::Classifier.new(standing.playthrough)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    begin
      intent = classifier.classify(line.typed)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      Reading.new(line: line, arm: arm.id, rep: rep, error: nil, seconds: elapsed,
                  answered_by: classifier.agent.current_model[:model],
                  raw: raw_answer(classifier),
                  answer: Eval::Classifier::Corpus::Answer.new(
                    intent: intent.action,
                    target: Playthrough::Classifier.label_for(intent.subject),
                    also_named: Playthrough::Classifier.label_for(intent.also_named)
                  ))
    rescue StandardError => error
      # A FAILED CALL HAS NO LATENCY, deliberately: how long it took to fail is
      # a fact about the failure and not about how fast this model answers, and
      # folding it into the median would make a flaky arm look slow instead of
      # flaky. The failure count and its error classes are the figure for it.
      Reading.new(line: line, arm: arm.id, rep: rep, answer: nil, answered_by: nil, raw: nil,
                  seconds: nil, error: "#{error.class}: #{error.message}")
    end
  end

  # THE PROVIDER'S OWN JSON for the call just made. `#recorded_chat` is the
  # non-building reader on purpose -- looking for a conversation must not create
  # one -- and `content_raw` is the column PR 97 kept.
  def raw_answer(classifier)
    stored = classifier.agent.recorded_chat&.messages&.where(role: "assistant")&.order(:id)&.last
    body = stored&.content_raw
    body.is_a?(String) ? JSON.parse(body) : body
  rescue JSON::ParserError
    nil
  end
end
