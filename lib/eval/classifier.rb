# THE CLASSIFIER'S OWN INSTRUMENT, and until now it had none.
#
# WHY IT EXISTS. `Playthrough::Classifier` runs on every single turn and is the
# only model call whose answer the engine ACTS on: a `move` writes
# `playthroughs.current_location_id`, a `take` moves an `items` row, a `talk`
# picks which character prompt is built. Everything else a model writes in this
# app is prose, and prose is measured -- `Story::Audit`, `Eval::Board`,
# `rake game:score`. The classifier was measured only by its misses, and only
# indirectly: `Playthrough::Drift` counts the turns on which a reach resolved to
# nothing and `Playthrough::Overreach` the turns on which a line named two
# things, and NEITHER OF THEM KNOWS WHETHER THE ANSWER WAS RIGHT. A drift row is
# written whether the player reached for a door that is not there or the model
# failed to see a door that is.
#
# THE RULING OF 2026-09-04 MADE THAT WORSE, which is why this is being built
# now. Before it, a classifier answer that lost half a line was a half-played
# turn; since it, `Playthrough::Classifier::Intent#refused?` is load-bearing
# copy -- a wrong resolution is a refusal the player reads, and a wrong
# `also_named` refuses a line that should have played. There is no instrument
# behind that at all.
#
# SO: A LABELLED CORPUS AND A REPLAY. `test/fixtures/files/classifier_corpus.yml`
# is typed lines with the answer written beside them by hand; `Eval::Classifier::Bench`
# replays them through the real `Playthrough::Classifier` against a fixed seeded
# world, so the closed sets the model is offered are exactly the ones the label
# was written against. What comes out is an accuracy per intent, a confusion
# matrix, the closed-set misses (right intent, wrong record), `also_named`
# precision and recall, refusal-kind agreement -- and a band across repetitions,
# on the same discipline as `EVALUATION.md`: a rate with no spread beside it
# invites exactly the false confidence the rest of this module exists to
# prevent.
#
# WHAT MAKES IT DIFFERENT FROM THE TWO INSTRUMENTS THAT ALREADY EXIST:
#
#   eval:run          reads NARRATION against the records. Costs dollars, noisy
#                     enough to need a rank test, never runs in CI.
#   game:sweep        reads THE RECORDS after a typed line, with the classifier
#                     switched off. Deterministic, free, asserts pass or fail.
#   eval:classifier   reads THE CLASSIFIER'S ANSWER against a hand-written
#                     label. Costs cents, needs the band because a provider is
#                     not deterministic even at temperature 0, and reports a
#                     rate rather than a pass -- and it has an OFFLINE FLOOR
#                     (`Eval::Classifier::Offline`) that says what the same
#                     corpus costs with no model at all, so what a classifier
#                     call is buying is a number and not an assumption.
#
# WHAT IT DELIBERATELY DOES NOT DO: change a prompt. This is the instrument, and
# a prompt tuned against the run that measured it is a prompt fitted to 300
# lines. Findings go to the PR body; `rake eval:classifier_compare` is how the
# next change is judged.
module Eval::Classifier
  # The corpus. YAML rather than JSON like its four siblings, and deliberately:
  # every line carries a `why` saying how its label was arrived at, and three
  # hundred of those in JSON is a file nobody audits. The frozen-ness is the
  # same -- it is checked in, it is in `Eval::MEASUREMENT_FILES`, and
  # `Eval::Classifier::CorpusTest` fails if a line's label contradicts the
  # closed set it was written against.
  CORPUS = Rails.root.join("test/fixtures/files/classifier_corpus.yml")

  # Where a bench run's numbers land, beside the `scores.json` an `eval:run`
  # set writes. A classifier set is its own file rather than a column in that
  # one, because the two measure different things over different corpora and a
  # set can legitimately hold one without the other.
  RESULTS = "classifier.json".freeze

  # THE ANSWER THE ENUM GIVES FOR "NOTHING ON THE LIST", as the corpus writes
  # it. `Playthrough::IntentSchema::NOTHING` is the model's side of the same
  # word; a corpus line says `target:` nothing by omitting it, and this is what
  # both are compared as.
  NONE = "nothing".freeze

  # THE FOUR OUTCOMES A LINE CAN HAVE AS FAR AS THE RULING IS CONCERNED, in the
  # order `Playthrough::Classifier::Intent#refused?` decides them. `:none` is
  # not a refusal -- it is the line the engine plays.
  REFUSALS = [ :none, *Playthrough::Refusal::KINDS ].freeze

  # THE INTENTS, out of the schema rather than copied. A word added there has to
  # show up in this board's confusion matrix without anybody remembering to add
  # it here.
  INTENTS = Playthrough::IntentSchema::INTENTS.map(&:to_sym).freeze

  def self.corpus = Corpus.load

  # A FINGERPRINT OF THE LINES A RUN MEASURED, stored on the set. Two bench sets
  # are only comparable if they scored the same corpus, and a corpus this size
  # is edited between runs -- so the digest is what lets
  # `rake eval:classifier_compare` say "these measured different lines" instead
  # of quietly reporting the difference between two files as a change in the
  # model.
  def self.digest(corpus = self.corpus)
    Digest::SHA256.hexdigest(corpus.lines.map { |line| [ line.id, line.typed, line.intent,
                                                         line.target, line.also_named ].join("\u0000") }.join("\n"))
                  .first(16)
  end

  # WHAT ONE REPETITION OF THE BENCH COSTS, priced off the registry the same way
  # `Eval::Cost` prices a sweep -- and measured, not modelled: 372 input tokens
  # and 20 output per call, the mean over the 61 real classifier calls in the
  # captain's own database on 2026-09-04. The classifier is the cheapest call in
  # the app by a wide margin, which is what makes a three-hundred-line bench
  # affordable at all.
  PER_CALL = { input: 372, output: 20 }.freeze

  def self.estimate(lines:, reps:, models:)
    calls = lines * reps
    models.sum do |model|
      Eval::Cost.price(model).of(calls * PER_CALL[:input], calls * PER_CALL[:output])
    end
  end
end
