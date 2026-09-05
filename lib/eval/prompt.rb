# THE NARRATOR'S OWN INSTRUMENT: ONE TURN, FIXED FACTS, THE DETERMINISTIC
# CHECKS, PER MODEL AND PER PROMPT VERSION.
#
# THE CAPTAIN'S WORDS, 2026-09-04: *"could we not build a small set of prompts
# and responses? ... a more targeted set of test cases where we are feeding the
# narrator facts and seeing how it handles them that would not require multiple
# turns."*
#
# WHY IT EXISTS. `rake eval:run` is the only thing that could judge a
# prompt-shaped change, and it judges it the expensive way: twenty-turn scripted
# runs across three worlds, dollars a comparison, four runs a side before
# `Eval::Noise` will say anything, and every figure entangled with which rooms
# the script happened to walk through. So the standing rule -- that no narration
# or prompt change lands until there is a testing method the captain trusts --
# had no cheap instrument behind it. This is that instrument, and the shape is
# the classifier bench's (`Eval::Classifier`, PR 119) applied to prose:
#
#   a FIXED CORPUS of single-turn cases, each one a complete moment out of the
#   records; ONE prose call per case on a named model under a named PROMPT
#   VERSION; the SAME deterministic checks `rake game:score` runs, over the
#   passage that came back; a BAND across repetitions, because two identical
#   runs disagree; and REAL / NOISE from `Eval::Noise` between two sets.
#
# WHAT IT MEASURES THAT NOTHING ELSE CAN. `Story::Scoreboard`'s three corpora
# score prose that already exists -- they cannot ask for prose. `rake eval:run`
# can ask for prose but only by playing a whole run, so a check's numerator and
# denominator both move when the script walks somewhere else. Here the facts are
# FIXED: the same room, the same floor, the same hands, the same item picked up,
# every repetition and every model. A difference between two sets is a
# difference in the prose and nothing else.
#
#   eval:run          plays whole runs. Dollars, noisy, the only thing that can
#                     measure pacing and a world in motion.
#   game:score        reads stored prose against the records. Free, offline, and
#                     it can only read what somebody already generated.
#   game:sweep        reads the RECORDS after a typed line, no model at all.
#   eval:classifier   reads the classifier's answer against a hand label.
#   eval:prompt       ASKS FOR ONE TURN OF PROSE against fixed facts and scores
#                     it. Cents, and the checks are the ones already measured
#                     for false positives on real prose.
#
# WHAT IT DELIBERATELY DOES NOT DO: change a prompt. This PR is the instrument;
# `ta-take-drop-narration` is its first consumer, and `rake eval:prompt_compare`
# is how that change gets judged. A prompt tuned against the run that measured
# it is a prompt fitted to a hundred cases.
#
# AND IT IS NOT A SUBSTITUTE FOR `rake eval:run`, which is worth saying because
# it is cheap enough to be treated as one. A single turn cannot show pacing, a
# world that moved, a check that reads two consecutive turns, or the drift a
# player suffers three turns after a narration invented a door. The protocol is:
# judge a prompt-shaped change here FIRST, confirm it there.
module Eval::Prompt
  # The corpus. YAML for the same reason the classifier's is: every case carries
  # a `why` saying what it is in the file for, and a hundred of those in JSON is
  # a file nobody audits.
  CORPUS = Rails.root.join("test/fixtures/files/prompt_corpus.yml")

  # Where a run's numbers land, beside `classifier.json` and `scores.json`. Its
  # own file, because a set may legitimately hold one, two or all three.
  RESULTS = "prompt.json".freeze

  # THE WORLDS THIS BENCH PLAYS, and the one it will not.
  #
  # `The Lunar Cartographer` is EXCLUDED and the reason is mechanical rather
  # than editorial: `WorldMechanic::ShuffleConnections` repoints its doorways on
  # the story's clock, and `Playthrough::Turn#play` catches the world up before
  # it does anything else. The exits in the prompt would therefore depend on
  # when the case was played, and a bench whose facts move is not a bench. Its
  # rooms are all stubs besides, so every `move` in it would pay for
  # `Location::Generator` -- two more calls, and the arrival prose measured
  # against a room the run had just invented.
  STORIES = [ "The Unrecorded Hour", "The Salt Assizes" ].freeze

  # AND THE HELD-OUT WORLD IS STILL HELD OUT HERE, reported apart and never
  # pooled -- `Eval::HELD_OUT`, the same convention `Eval::Board` keeps. It
  # matters more here than anywhere, not less: this bench exists so a prompt can
  # be tuned against a measurement, and a prompt tuned against every case in the
  # file is a prompt fitted to the file. Tune on `The Unrecorded Hour`, read the
  # result on `The Salt Assizes`.
  def self.held_out?(story) = Eval.held_out?(story)

  # WHAT A CASE ASKS THE ENGINE TO DO, and it is the classifier's own enum
  # rather than a list of this bench's own. A case declares the answer the
  # classifier would have given -- `Playthrough::Classifier::Intent` -- and the
  # bench hands that to `Playthrough::Turn#play` in place of a model call, so
  # the branch a case takes is chosen by the app and never here. See
  # `Eval::Prompt::Bench#intent_for`.
  ACTS = Playthrough::IntentSchema::INTENTS.map(&:to_sym).freeze

  # THE ONE ACT THIS BENCH CANNOT MEASURE, stated with its reason because it is
  # a hole in the coverage and not an oversight.
  #
  # A `talk` turn's prose is `InteractionAgent`'s second pass, and that pass
  # sends NO instructions: its prose rules live inside the per-turn user prompt
  # with the character's name and pronouns interpolated through them. There is
  # therefore no instruction text to version -- a digest of that prompt is a
  # digest of the cast -- and a bench whose whole point is "per prompt version"
  # cannot honestly carry a pass it cannot version. It costs two model calls a
  # case besides, where every other shape costs one.
  #
  # What that leaves uncovered is `interaction-narration` prose, which is real
  # and is measured today by `rake eval:run` and `rake game:score` exactly as
  # before. Closing it means giving that pass its own instructions, which is a
  # PROMPT CHANGE and therefore not this PR's to make.
  UNSUPPORTED_ACTS = { talk: "the interaction narrator sends no instructions to version, and costs two calls" }.freeze

  # THE PROSE PASSES A CASE CAN LAND IN, named because the board groups by them
  # and they cost different amounts. Which one a case reaches is the app's
  # decision (`Playthrough::Turn#play`), read back off the conversation the turn
  # produced rather than declared in the corpus.
  PASSES = %w[narration arrival].freeze

  # WHAT ONE CALL COSTS, PER PASS, priced the way `Eval::Cost` prices a sweep --
  # measured, not modelled. The mean over the real prose calls in the captain's
  # own database on 2026-09-05: 35 `narration` calls and 25 `arrival` calls.
  # They are not the same number and must not be averaged: an arrival inlines
  # the universe and answers in a schema'd paragraph, a narration is handed the
  # moment and streams two.
  PER_CALL = {
    "narration" => { input: 762, output: 440 },
    "arrival" => { input: 1_112, output: 158 }
  }.freeze

  # CHECKS A SINGLE-TURN CASE CANNOT ANSWER, AND WHY -- reported unavailable
  # rather than as a rate, on the rule `Story::Scoreboard::Corpus` and
  # `Eval::UNAVAILABLE_TO_A_SCRIPT` both follow. A zero here would be a lie, and
  # a clean-looking one.
  #
  # `unreachable_transition` compares two consecutive scenes against the graph.
  # A case is one turn, and the one turn that moves anybody moves them through
  # `Playthrough::Turn#move_to` along an edge the records have -- so the check
  # could never fire here whatever the prose said. It is a check on the app's
  # own movement rather than on prose, and it stays live where two turns exist.
  #
  # `reached_for_nothing` counts a `Playthrough::Drift` row: the player reaching
  # for something the records do not have, AFTER reading a narration. That
  # inference needs a player and a next turn, and a case has a fixed typed line
  # and no next turn -- the same structural argument
  # `Eval::UNAVAILABLE_TO_A_SCRIPT` makes for a scripted run, one step stronger.
  #
  # `named_more_than_one` is a fact about how the case's own line was phrased,
  # and the lines here are chosen. It would measure the corpus.
  #
  # `still_run` is a run of four turns with nothing changing. There is one turn.
  UNAVAILABLE_TO_A_CASE = {
    unreachable_transition: "a case is one turn, and the one turn that moves walks an edge the records have",
    reached_for_nothing: "a drift row needs the turn AFTER the narration, and a case has no next turn",
    named_more_than_one: "a case types a fixed line, so what it named measures the corpus, not the game",
    still_run: "four turns of nothing needs four turns"
  }.freeze

  def self.unavailable_to_a_case?(code) = UNAVAILABLE_TO_A_CASE.key?(code.to_sym)

  # THE CHECKS THIS BENCH SCORES, in `Story::Scoreboard::CHECKS` order so one
  # reading order serves every board in the repo. Everything not named
  # unavailable above.
  def self.checks = Story::Scoreboard::CHECKS.keys - UNAVAILABLE_TO_A_CASE.keys

  def self.corpus = Corpus.load

  # A FINGERPRINT OF THE CASES A RUN MEASURED, stored on the set. Two sets are
  # only comparable if they scored the same cases against the same facts, and a
  # corpus this size is edited between runs -- so the digest is what lets
  # `rake eval:prompt_compare` say "these measured different cases" instead of
  # quietly reporting the difference between two files as a change in the
  # prompt. The same field and the same job as `Eval::Classifier.digest`.
  def self.digest(corpus = self.corpus)
    Digest::SHA256.hexdigest(
      corpus.cases.map { |kase| [ kase.id, kase.position, kase.typed, kase.act, kase.target ].join(" ") }.join("\n")
    ).first(16)
  end

  # `models` is `Eval::Classifier::Arm`s -- the arm selector is shared rather
  # than copied, because "one model, named explicitly, with the rotation off" is
  # the same requirement here as there and a second implementation of it would
  # be a second thing to keep honest. Each arm prices itself.
  def self.estimate(cases:, reps:, models:)
    tokens = cases.each_with_object({ input: 0, output: 0 }) do |kase, total|
      per = PER_CALL.fetch(kase.pass, PER_CALL["narration"])
      total[:input] += per[:input] * reps
      total[:output] += per[:output] * reps
    end

    Eval::Classifier::Arm.all(models).sum { |arm| arm.price.of(tokens[:input], tokens[:output]) }
  end
end
