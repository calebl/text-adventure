# THE AUTOMATED HALF OF THE EVALUATION LOOP: generate runs, score them, and say
# whether a difference between two sets of runs is real.
#
# `Story::Audit` and `Story::Scoreboard` (`ta-eval-loop`) can already read
# stored prose against the records. What they had was nowhere to read it FROM
# except the captain's own playthroughs and a frozen file of loose passages --
# which is why three of their checks report *unavailable*: a passage with no
# records around it cannot be checked against records. This module produces the
# missing corpus. It plays the real loop against a fresh copy of a seeded world,
# keeps every row the turn wrote, and scores the result.
#
# WHAT IT IS FOR, in the captain's words: *"I'm fine with the loop being manual
# initially. I just want more confidence that changes we are making are
# improving results."* Confidence, not automation. So the headline output is not
# a score -- it is a score WITH ITS NOISE FLOOR, because generated runs are
# model output and two identical runs do not agree with each other. A board that
# does not say how far its own numbers wander invites exactly the false
# confidence it was built to prevent. `Eval::Noise` is that half, and
# `EVALUATION.md` is the protocol.
#
# THE HAZARD THIS IS BUILT AGAINST. The cheapest way to stop the narrator
# contradicting the records is to make it say less: vague prose asserts nothing
# and so contradicts nothing. That is not an edge case, it is the dominant
# strategy for anything optimising these numbers. `Eval::Richness` counts what
# the prose COMMITS TO -- rooms, exits, items and people the records know,
# named in the passage -- and the board prints it beside the defect counts and
# NEVER folds it in. A change that buys a lower contradiction rate with blander
# prose has to show up as a loss somewhere, and this is where.
#
# WHAT IS DELIBERATELY NOT HERE: a prose score, a judge model, an aggregate
# quality number. See `Story::Scoreboard`'s header and
# `data/ta-model-bench/report.md` §9.
module Eval
  # THE THREE SEEDED WORLDS THE SWEEP PLAYS, and the one of them that is held
  # out.
  #
  # HOLDING ONE OUT IS A CONVENTION, DOCUMENTED RATHER THAN ENFORCED, and that
  # is a deliberate choice about where the effort goes today: the anti-gaming
  # machinery matters when an agent is driving the loop, and the captain has
  # said that is not yet. What it buys now is still real -- the two tuning
  # worlds are the ones every check in `Story::Audit` was measured against
  # (`narration_corpus.json` and `eval_corpus.json` are drawn from them), and
  # `The Salt Assizes` is a world no check has ever seen. A rate that holds up
  # on it is a rate that did not come from fitting the passages.
  #
  # The rule, for whoever automates this later: TUNE ON `TUNING`, REPORT ON
  # `HELD_OUT`, AND NEVER READ A HELD-OUT PASSAGE WHILE CHANGING A CHECK.
  # `Eval::Board` prints the two apart and labels them, so an accidental
  # pooling is visible in the output.
  TUNING = [ "The Unrecorded Hour", "The Lunar Cartographer" ].freeze
  HELD_OUT = "The Salt Assizes".freeze

  STORIES = (TUNING + [ HELD_OUT ]).freeze

  def self.held_out?(title) = title.to_s == HELD_OUT

  # THE FILES THAT CONSTITUTE THE MEASUREMENT -- the manifest an improving agent
  # is to leave alone while it changes the game. Declared here so the rule can
  # be stated as a list rather than as an argument about which files count, and
  # printed by `rake eval:manifest` with a digest of each, so a before/after
  # snapshot can prove nothing in it moved.
  #
  # NOT ENFORCED. There is no hook and no lock, on purpose (see the note on
  # `HELD_OUT`). It is a declaration for the skill that will drive this loop.
  MEASUREMENT_FILES = %w[
    app/models/story/audit.rb
    app/models/story/audit/prose.rb
    app/models/story/scoreboard.rb
    app/models/story/scoreboard/baseline.rb
    app/models/story/scoreboard/corpus.rb
    app/models/story/scoreboard/transitions.rb
    lib/eval.rb
    lib/eval/board.rb
    lib/eval/comparison.rb
    lib/eval/cost.rb
    lib/eval/noise.rb
    lib/eval/richness.rb
    lib/eval/run_score.rb
    lib/eval/run_set.rb
    lib/eval/script.rb
    lib/eval/transcript.rb
    lib/tasks/eval.rake
    script/eval_run.rb
    db/eval_baseline.json
    test/fixtures/files/eval_corpus.json
    test/fixtures/files/narration_corpus.json
    test/fixtures/files/whole_run_corpus.json
    test/fixtures/files/transition_corpus.json
  ].freeze

  # CHECKS A SCRIPTED RUN CANNOT ANSWER, AND WHY -- reported unavailable rather
  # than as a rate, on the same rule `Story::Scoreboard::Corpus` follows for the
  # checks a loose passage cannot answer. A zero here would be a lie.
  #
  # `reached_for_nothing` counts turns on which the player reached for something
  # the records do not have. It is in `Story::Audit` as DRIFT -- evidence about
  # the narrator INVENTING things, measured by its consequences: the player
  # walks at a door because the prose put a door there.
  #
  # THAT INFERENCE NEEDS A PLAYER, and a sweep has a script. The captain's
  # ruling, 2026-09-03: *"if someone reaches for an item that is not there and
  # the classifier catches and the narrator says no, then everything is working
  # correctly and that should NOT be getting flagged as an issue."* Exactly so,
  # and the reason is structural rather than a matter of degree: A SCRIPT CANNOT
  # BE MISLED BY PROSE. It types the same words whatever the narrator wrote, so
  # a drift row on a generated run says something about the script -- or about
  # the classifier refusing a command it should have resolved -- and nothing
  # whatever about invention.
  #
  # The evidence agreed before the ruling did. Across 44 drift rows in every
  # sweep run to date, every single one was either a turn written to reach for
  # something absent or a turn whose author had lost track of which room the
  # script was in. Not one was a player misled by a narration.
  #
  # SO IT STAYS LIVE WHERE IT MEANS SOMETHING -- `rake game:score`'s database
  # corpus, where a person really typed the commands -- and is unavailable here.
  # What replaces it for a sweep is `Eval::Board`'s script-divergence line: the
  # turns whose branch was not the one the script expected, reported next to the
  # spend as a fact about the harness rather than among the defect counts.
  # `named_more_than_one` is out for the SAME structural reason, one step
  # further along. A script types a fixed line however the game answered, so
  # whether a turn named two things is a fact about how its author phrased it
  # and not about the game -- and the scripts are full of such lines:
  # "go down the stairs and out into Mournwell Lane", "look at the boots by the
  # door and the dark iridescence dried on them". A rate over those measures
  # the yml files.
  #
  # AND A CLEAN READING WOULD BE THE WORSE OUTCOME: with no line overreaching,
  # the check reads 0 flagged out of every typed turn, which is a rate it never
  # earned. That is precisely what "unavailable, never zero" exists to stop.
  # It stays live on `rake game:score`'s database corpus, where somebody really
  # typed the commands, which is the only place the number means anything.
  # AND THE TWO TRANSITION CHECKS ARE DELIBERATELY NOT HERE, which is worth
  # saying next to the two that are. `take_denied` and `pickup_invented` read a
  # narration against a state change the APP made -- the row moved before any
  # prose existed -- so what they measure is what the narrator did with a fact
  # it was handed, and a script's fixed line has no bearing on that. They are
  # the first checks on this board that are fully available to a sweep AND fully
  # available offline, which is what makes the take/drop prose fix judgeable by
  # `rake eval:compare` at all.
  UNAVAILABLE_TO_A_SCRIPT = {
    reached_for_nothing: "a script cannot be misled by prose, so a drift row here measures the script, not the game",
    named_more_than_one: "a script types a fixed line, so what it named measures the script's phrasing, not the game"
  }.freeze

  def self.unavailable_to_a_script?(code) = UNAVAILABLE_TO_A_SCRIPT.key?(code.to_sym)

  # Where a sweep's runs land. Under `tmp/` because a run is a working artifact:
  # it holds a whole SQLite database per run and is regenerated by paying for it
  # again, so nothing here is checked in.
  ROOT = "tmp/eval".freeze

  def self.root = Rails.root.join(ROOT)

  def self.set_path(name) = root.join(name)

  # The two summary statistics every part of this module reaches for, in one
  # place so a rate and its spread are never averaged two different ways.
  # WHICH ONE TO USE IS A JUDGEMENT PER FIGURE and both are used deliberately:
  # see `Eval::Richness::Summary` for why length is a median and commitments
  # are a mean.
  def self.median(values)
    sorted = Array(values).compact.sort
    return 0.0 if sorted.empty?

    middle = sorted.size / 2
    sorted.size.odd? ? sorted[middle].to_f : (sorted[middle - 1] + sorted[middle]) / 2.0
  end

  def self.mean(values)
    rows = Array(values).compact
    rows.empty? ? 0.0 : rows.sum.fdiv(rows.size)
  end
end
