# THE ROOM-BUILDER'S OWN INSTRUMENT: ONE STUB, FIXED FACTS, THE DETERMINISTIC
# CHECKS, PER MODEL AND PER PROMPT VERSION.
#
# THE CAPTAIN'S STANDING TESTING RULE, 2026-09-04: *"could we not build a small
# set of prompts and responses? ... a more targeted set of test cases where we
# are feeding the narrator facts and seeing how it handles them that would not
# require multiple turns."* And the rule that stands over every prompt in the
# repo, 2026-09-06: *"we should always have a baseline for evaluating a prompt
# before we decide to change it."*
#
# WHY IT EXISTS. `Location::Generator` sends the three most expensive prompt
# blocks in the game -- WHO IS HERE, WHAT IS LYING HERE and THE WAYS OUT -- and
# until this file none of them had an instrument at all. The narrator has one
# (`rake eval:prompt`), the classifier has one (`rake eval:classifier`), and
# realization had judgement: the cast fix shipped on it, the roadmap-era prompt
# findings could not be measured either way, and the one number anybody has for
# any of this is a hand count -- 36% of generated exits restating a place the
# story already had (`data/ta-quest-progress-scout/report.md` D5, confirmed by
# `data/ta-neohack-scout/report.md` §3.2). A hand count is not a baseline: it
# cannot be re-run, it has no band, and no prompt change can be judged against
# it.
#
#   eval:run          plays whole runs. Dollars, noisy, the only thing that can
#                     measure pacing and a world in motion.
#   game:score        reads stored prose against the records. Free, offline, and
#                     it can only read what somebody already generated.
#   game:sweep        reads the RECORDS after a typed line, no model at all.
#   eval:classifier   reads the classifier's answer against a hand label.
#   eval:prompt       asks for ONE TURN OF PROSE against fixed facts.
#   eval:realization  ASKS FOR ONE ROOM against a fixed stub, and scores the
#                     ANSWER against the records the room was built from.
#
# WHAT IT MEASURES, AND WHY EVERY FIGURE IS A RECORD AND NOT A READING OF PROSE.
# The standing constraint (AGENTS.md) is that nothing may depend on the narrator
# obeying its prompt, and the corollary for an instrument is that nothing may
# depend on a checker UNDERSTANDING prose. So nearly every check here is a set
# comparison the app could have made itself: a name the model wrote against the
# closed set of names the prompt handed it, a count against the allowance the
# prompt stated, an exit against the list of places that already exist. What the
# prompt SAID is measurable because the prompt said a number or a list, and the
# answer either matched it or did not. `Eval::Realization::Scorer` is the whole
# of it, and the checks in `Scorer::KEYWORD_CHECKS` -- the ones that have to
# READ prose to get their side of the comparison -- are each named for what it
# can actually see rather than for what it would like to mean.
#
# WHAT IT DELIBERATELY DOES NOT DO: change a prompt. This is the instrument. The
# prompt half of `ta-room-people-count`, the exits findings and the bench cases
# of `ta-narrated-refusal` are its consumers, and each of them is judged with
# `rake eval:realization_compare` against a baseline bought before the change.
#
# AND IT IS NOT A SUBSTITUTE FOR `rake eval:run`. A realization measured on its
# own cannot show what the room is like to walk into three turns later, whether
# the exits it wrote led anywhere a player wanted to go, or what the description
# did to the narration that followed it. The protocol is the prompt bench's:
# judge here FIRST, confirm there.
module Eval::Realization
  # The cases. YAML for the classifier corpus's reason: every case carries a
  # `why` saying what it is in the file for, and a hundred of those in JSON is a
  # file nobody audits.
  CORPUS = Rails.root.join("test/fixtures/files/realization_corpus.yml")

  # Where a run's numbers land, beside `prompt.json` and `classifier.json`. Its
  # own file, because a set may legitimately hold any of them.
  RESULTS = "realization.json".freeze

  # THE SET THIS TREE'S PROMPTS WERE LAST MEASURED ON, under `db/eval` so it
  # survives a clean clone. It is the answer to "what is the baseline" as a
  # RECORD rather than as a thing somebody remembers, which is what the
  # captain's standing rule of 2026-09-06 needs in front of it.
  #
  # MOVING IT IS WHAT RE-BASELINING IS. `Eval::Realization::KeptSetTest` holds
  # this set to today's corpus digest AND to today's prompt digest
  # (`Eval::Realization::Version.offline`), so a prompt edited without a run to
  # judge it is a FAILING TEST rather than a judgement nobody could make. Point
  # it at the after side once the change has been judged, and never before.
  #
  # AND A CORPUS SCHEMA CHANGE RE-BASELINES IT TOO, WHICH IS THIS SET AND WAS THE
  # ONE BEFORE IT. Nothing in the prompts moved either time -- `prompt_digest` is
  # the same string across `room-people-after`, `kind-to-corpus-after` and this
  # -- but the corpus first grew the fields a case promoted out of
  # `Lab::Realization` carries, and then (the captain's Call 6 of 2026-09-08)
  # widened `expects_inside` from a boolean to the four quantifiers of
  # `Lab::Exits::QUANTIFIERS`, which is a change in what a case may CLAIM and so
  # in what the two inside checks may be judged on. The digest folds every field
  # that changes what was measured, so each time the old set stopped being a
  # baseline for this tree while remaining a true reading of these prompts --
  # exactly the state this constant exists to make visible.
  #
  # THE EARLIER SETS ARE KEPT AS HISTORY AND ARE NOT REWRITTEN. `room-people-after`
  # is still the before side of the room-people change and `kind-to-corpus-after`
  # the before side of this one; both were bought on the boolean label and
  # `Eval::Realization::Scorer::Reading#inside_quantifier` reads it as the
  # quantifier it always meant, so they score identically today.
  BASELINE = "exits-quantifier-after".freeze

  # WHERE A CASE'S WORLD IS READ FROM, IN ORDER. The seeded worlds first, so a
  # case against `The Salt Assizes` measures the file every other instrument in
  # the repo measures; then the bench's own fixture worlds, which is how a
  # GENERATED world gets in here at all.
  #
  # A generated world cannot be a seeded one. `db/seeds/worlds` is loaded by
  # `db/seeds.rb` into every development database and into `Eval::Base`'s base
  # world, so putting `The Iron Gate Descends` there would add a fourth world to
  # every sweep, every doctor run and every fresh clone -- a change to the game
  # made as a side effect of building an instrument. It lives under
  # `test/fixtures/files/worlds/` instead, which is where the frozen inputs to a
  # measurement already live, and `rake game:export` is how it got there.
  #
  # AND THE SWEEP'S OWN WORLDS ARE READ LAST, for the one thing only they have:
  # A LAID-OUT INTERIOR. `The Quay House` is the only world in the repository
  # with a building in it, its floor plan is `Location::Interior`'s own output
  # exported with `rake game:export`, and it is already held to every standard a
  # seeded world is (`EngineSweep::WORLDS`). A second copy of that plan under
  # this bench's own root would be a second floor plan to keep in step with the
  # generator, which is exactly the drift `Eval::Realization::Stage` refuses to
  # let a case's FACTS have.
  #
  # IT IS READ LAST BECAUSE IT IS THE LEAST CANONICAL OF THE THREE, and that is
  # all the order buys. `.world_file` takes the FIRST root that has the file, so
  # a duplicate under `test/fixtures/files/worlds/` would WIN over the playable
  # copy and the sweep's own world would go unread -- which is a reason never to
  # make one, not a protection against it. Every world named here exists in
  # exactly one root.
  WORLD_ROOTS = [ "db/seeds/worlds", "test/fixtures/files/worlds", "lib/engine_sweep/worlds" ].freeze

  def self.world_file(story)
    slug = WorldSeed.slug(story)
    WORLD_ROOTS.lazy.map { |root| Rails.root.join(root, "#{slug}.yml") }.find(&:exist?)
  end

  # THE WORLDS THIS BENCH BUILDS ROOMS IN, and one of them is a world the prompt
  # bench refuses.
  #
  # `The Lunar Cartographer` IS PLAYED HERE. `Eval::Prompt::STORIES` leaves it
  # out because `WorldMechanic::ShuffleConnections` repoints its doorways on the
  # story's clock and `Playthrough::Turn#play` catches the world up before it
  # narrates -- so a prompt bench case's exits would depend on when it ran. THIS
  # BENCH PLAYS NO TURN. It stands a stub up and realizes it; nothing advances a
  # clock, no `Scene` is written, and `WorldMechanic` is never asked to run. The
  # doorways are therefore exactly the ones the seed file lists, on the
  # hundredth repetition as on the first.
  #
  # AND IT IS THE ONE WORLD WITH MONSTERS IN IT. `Universe::Generator` marks no
  # race `monstrous` (see `Location::Danger`'s header), so a generated world's
  # bestiary is empty and a dangerous room in it draws an ordinary person.
  # `The Lunar Cartographer` is hand-authored and has the Nocturna-Blighted,
  # which is what makes the monstrous half of the cast prompt judgeable at all.
  #
  # `The Iron Gate Descends` is a GENERATED world, which is the point of it: the
  # measured exit defect came out of a generated world's rooms, and a corpus of
  # nothing but hand-authored seeds would be a corpus of worlds a person wrote
  # the neighbours of.
  #
  # `The Quay House` IS THE ONE WORLD WITH AN INSIDE, and it is here for slice
  # 3: a room of a laid-out interior is realized on different terms from every
  # other room in the game -- its ways out are the ENGINE's, so no exits call is
  # made at all, and the detail prompt is handed the room's own floor plan as
  # fact (`Location::Plan`). That is a prompt shape nothing else in this corpus
  # can reach, and the check it exists to feed
  # (`size_the_records_do_not_hold`) is unjudgeable anywhere else.
  STORIES = [
    "The Unrecorded Hour", "The Lunar Cartographer", "The Salt Assizes", "The Iron Gate Descends",
    "The Quay House"
  ].freeze

  # AND THE HELD-OUT WORLD IS STILL HELD OUT, reported apart and never pooled --
  # `Eval::HELD_OUT`, the convention every board in this repo keeps. Tune on the
  # rest, read the result on `The Salt Assizes`.
  def self.held_out?(story) = Eval.held_out?(story)

  # WHAT ONE REALIZATION COSTS, PER CALL, priced the way `Eval::Cost` prices a
  # sweep -- measured, not modelled. The mean over the real realization calls in
  # the captain's own database on 2026-09-06: 20 `detail` calls and 12 `exits`
  # calls, the difference being the rooms that arrived at their exit cap and
  # were never asked (`Location::Generator#write_exits!`).
  #
  # THEY ARE NOT THE SAME NUMBER AND MUST NOT BE AVERAGED. The detail call
  # inlines the universe and answers with a room, its floor and its cast; the
  # exits call is asked in the SAME conversation, so its input carries the
  # detail prompt and the detail answer as well as its own -- which is why the
  # cheaper call has the larger input.
  PER_CALL = {
    "detail" => { input: 1_399, output: 385 },
    "exits" => { input: 1_848, output: 144 }
  }.freeze

  # THE TWO CALLS ONE REALIZATION MAKES, in the order `Location::Generator`
  # makes them. Named because the board groups by them and they cost different
  # amounts.
  CALLS = PER_CALL.keys.freeze

  # WHAT THIS BENCH CANNOT ANSWER, AND WHY -- reported unavailable rather than
  # as a rate, on the rule `Story::Scoreboard::Corpus` and
  # `Eval::UNAVAILABLE_TO_A_SCRIPT` both follow. A zero here would be a lie, and
  # a clean-looking one.
  #
  # These are the questions a reader of this board will assume it answered,
  # which is exactly why each is named with its reason instead.
  UNAVAILABLE_TO_A_REALIZATION = {
    description_is_good: "there is no deterministic reader of whether a paragraph is worth reading, " \
                         "and a judge model would be a second model to keep honest -- see Story::Scoreboard",
    the_exit_led_somewhere_worth_going: "that is a fact about the room on the far side, which does not " \
                                        "exist until somebody walks through and pays for it",
    the_room_fits_its_neighbours: "the description is told not to describe its neighbours " \
                                  "(Location::DetailSchema), so agreement with them is not asked for",
    the_cast_is_worth_talking_to: "a person's sheet is judged by the conversation it produces, " \
                                  "which is InteractionAgent's call and not this one",
    door_in_a_wall_the_records_do_not_hold: "a description that puts a door in a wall the plan does not " \
                                            "hold cannot be told from one that describes a DOORLESS wall " \
                                            "beside a door without parsing the sentence, and six measured " \
                                            "grammars each admitted a shape the one before it did not -- " \
                                            "Story::Audit's header carries the record. The prompt still " \
                                            "states every door's wall (Location::Plan); only the check is gone"
  }.freeze

  def self.unavailable_to_a_realization?(code) = UNAVAILABLE_TO_A_REALIZATION.key?(code.to_sym)

  # THE CHECKS THIS BENCH SCORES. Every one of them compares what the model
  # WROTE against something the PROMPT STATED -- a number, or a closed list of
  # names -- so each is a set comparison rather than a reading. The order is the
  # trust ordering the rest of the repo prints in: what the records prove first.
  def self.checks = Eval::Realization::Scorer::CHECKS.keys

  def self.corpus = Corpus.load

  # A FINGERPRINT OF THE CASES A RUN MEASURED, stored on the set. Two sets are
  # only comparable if they built the same rooms out of the same worlds, and a
  # corpus this size is edited between runs -- so the digest is what lets
  # `rake eval:realization_compare` say "these measured different cases"
  # instead of quietly reporting the difference between two files as a change in
  # the prompt. The same field and the same job as `Eval::Prompt.digest`.
  #
  # EVERY FIELD THAT CHANGES WHAT WAS MEASURED IS IN IT, and the two that are
  # easiest to leave out are the two that do not stage anything:
  # `expects_new_ground` decides whether `no_new_ground` is judgeable at all and
  # gates `exit_already_reachable`'s dead-end case, and `shape` chooses the
  # designated case behind `prompt_digest` (`Eval::Realization::Version`). Flip
  # either and the rates move; leave either out and the comparison would credit
  # the movement to the prompt. `expects_inside` is in it for exactly that
  # reason and it is the newest of them: it decides whether the two inside
  # checks may be judged on a case at all -- and it is folded NORMALISED
  # (`Case#expects_inside_quantifier`), so the boolean a case was written with
  # before the captain's Call 6 of 2026-09-08 and the quantifier it means digest
  # alike. Re-spelling a label is not a measurement; widening what a label can
  # SAY is, which is why this tree needed a new baseline for the widening itself.
  # `Eval::Classifier.digest` carries its own label fields for the same reason.
  # `why` is NOT in it -- rewriting the sentence that says why a case is here
  # measures nothing new.
  #
  # AND A PROMOTED CASE'S OWN FIELDS ARE IN IT, ALL OF THEM. `teaser` is the
  # prompt's second sentence about the room and changing it changes the room that
  # is asked for; `inside` and `population` are what a real exits call supplied
  # and both are stated to the model; and the whole `expects_*` block is in it on
  # `expects_inside`'s precedent -- an expectation decides which figures a case
  # may be judged on, so editing one moves the rates without touching a prompt,
  # and a comparison across the edit would credit the movement to the prompt.
  # That is the failure this method exists to prevent, said about the newest keys.
  def self.digest(corpus = self.corpus)
    Digest::SHA256.hexdigest(
      corpus.cases.map { |kase|
        [ kase.id, kase.story, kase.room, kase.teaser, kase.reached_from, kase.danger, kase.inside,
          kase.population, kase.shape,
          kase.expects_new_ground.inspect, kase.expects_inside_quantifier.inspect,
          kase.expects_danger_at_least.inspect, kase.expectation_line,
          kase.also_reaches.join("|"),
          kase.absent.join("|"), kase.unwritten.join("|") ].join(" ")
      }.join("\n")
    ).first(16)
  end

  # `models` is `Eval::Classifier::Arm`s -- the arm selector is shared rather
  # than copied, because "one model, named explicitly, with the rotation off" is
  # the same requirement here as in the other two benches and a second
  # implementation of it would be a second thing to keep honest.
  #
  # PRICED AT TWO CALLS A CASE, which is what a realization costs when the room
  # has room for another way out. A case whose stub is already at the exit cap
  # costs one, and so does every INTERIOR ROOM -- its ways out are the engine's
  # and `Location::Generator#write_exits!` asks for none. The estimate models
  # neither: an estimate that comes in under is a nasty surprise and one that
  # comes in over is not (`Eval::Cost`'s rule).
  def self.estimate(cases:, reps:, models:)
    per = CALLS.sum { |call| PER_CALL.fetch(call)[:input] }
    out = CALLS.sum { |call| PER_CALL.fetch(call)[:output] }
    tokens = { input: cases.size * reps * per, output: cases.size * reps * out }

    Eval::Classifier::Arm.all(models).sum { |arm| arm.price.of(tokens[:input], tokens[:output]) }
  end
end
