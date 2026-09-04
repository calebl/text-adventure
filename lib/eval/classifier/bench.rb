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
# PER MODEL. `OPENROUTER_MODEL` is unshifted onto `BaseAgent::REMOTE_MODEL_IDS`,
# which is the app's own pin and what `script/eval_run.rb` uses -- so an arm asks
# the model it names FIRST and the rotation is still behind it. The model that
# actually answered is read back off the agent (`BaseAgent#current_model`) and
# any line answered by a different one is counted and reported as a ROTATION
# rather than quietly attributed to the arm. An arm with rotations is an arm
# whose purity is stated.
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
  Reading = Data.define(:line, :arm, :rep, :answer, :answered_by, :raw, :error) do
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

    def rotated? = !answered_by.nil? && answered_by != arm

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

    def to_h = { arm:, rep:, accuracy: accuracy.round(4), intent_accuracy: intent_accuracy.round(4),
                 strict_accuracy: strict_accuracy.round(4), refusal_agreement: refusal_agreement.round(4),
                 closed_set_misses:, rotations:, failures:, readings: rows }

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
        answered_by: reading.answered_by, error: reading.error }
    end
  end

  attr_reader :corpus, :arms, :reps, :io

  def initialize(corpus: Eval::Classifier.corpus, arms: nil, reps: 3, io: $stdout)
    @corpus = corpus
    @arms = arms || BaseAgent::REMOTE_MODEL_IDS
    @reps = reps
    @io = io
  end

  # Returns an `Eval::Classifier::Result`. Raises only what the classifier
  # raises after its own rotation is exhausted -- and not even then: a line that
  # failed is recorded as a failure and the pass keeps going, because a provider
  # dropping one call in three hundred must not cost the whole run.
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

    arms.each do |arm|
      with_model_pinned(arm) do
        (1..reps).each do |rep|
          Eval::Classifier::Stage.open(corpus.positions) { |stages| passes << play(arm, rep, stages) }
        end
      end
    end

    Eval::Classifier::Result.new(corpus_size: corpus.size, corpus_digest: Eval::Classifier.digest(corpus),
                                 arms: arms, reps: reps, passes: passes)
  end

  private

  def play(arm, rep, stages)
    io&.print format("  %-28s rep %d ", arm, rep)
    readings = corpus.lines.map { |line| read(line, stages.fetch(line.position), arm, rep) }
    pass = Pass.new(arm: arm, rep: rep, readings: readings)
    io&.puts format("%3d/%-3d right (%.3f), %d closed-set misses%s%s",
                    pass.scored.count(&:right?), pass.scored.size, pass.accuracy, pass.closed_set_misses,
                    pass.rotations.positive? ? ", #{pass.rotations} ROTATED" : "",
                    pass.failures.positive? ? ", #{pass.failures} FAILED" : "")
    pass
  end

  # ONE LINE. A fresh `Playthrough::Classifier` per line, because the agent it
  # memoizes is one conversation and the classifier is stateless by design --
  # "there is nothing in last turn's exchange worth replaying".
  def read(line, standing, arm, rep)
    classifier = Playthrough::Classifier.new(standing.playthrough)
    intent = classifier.classify(line.typed)

    Reading.new(line: line, arm: arm, rep: rep, error: nil,
                answered_by: classifier.agent.current_model[:model],
                raw: raw_answer(classifier),
                answer: Eval::Classifier::Corpus::Answer.new(
                  intent: intent.action,
                  target: Playthrough::Classifier.label_for(intent.subject),
                  also_named: Playthrough::Classifier.label_for(intent.also_named)
                ))
  rescue StandardError => error
    Reading.new(line: line, arm: arm, rep: rep, answer: nil, answered_by: nil, raw: nil,
                error: "#{error.class}: #{error.message}")
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

  # THE APP'S OWN PIN, put back afterwards. `BaseAgent.remote_model_options`
  # unshifts `OPENROUTER_MODEL` onto the list, so an arm asks its model first
  # and the rotation is still there behind it -- which is what makes a failed
  # call a rotation to report rather than a lost line.
  def with_model_pinned(model)
    was = ENV["OPENROUTER_MODEL"]
    ENV["OPENROUTER_MODEL"] = model
    yield
  ensure
    ENV["OPENROUTER_MODEL"] = was
  end
end
