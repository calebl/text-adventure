# THE REALIZATION LAB: ONE ROOM BUILT FROM A KIND OF PLACE HE TYPED, WATCHED IN
# SEQUENCE, JUDGED, AND COUNTED AGAINST WHAT HE SAID THE PICKS SHOULD BE.
#
# THE CAPTAIN'S ASK, 2026-09-07, verbatim: *"I want a way to be able to manually
# test location/room generation with a universe to ensure it is aligned with what
# I want. I'm imagining a UI that allows me to create a location based on a
# prompt to see how it happens and if it is happening how I want it too. I can
# run through a set of samples, score them and then we can use that to create
# alignment and then maintain alignment in the future."* And the clause that
# decided the shape of everything below: *"I want to make sure it is picking what
# I think it should MOST OF THE TIME."*
#
# A LAB IS NOT A BENCH, AND THE TWO WORDS HAVE TO STAY TELLABLE APART.
#
#   `Eval::Realization`  a FIXED corpus, judged by record checks, replayed
#                        offline for nothing, reporting rates over CHECKS. It is
#                        the instrument a prompt change is measured with.
#   `Lab::Realization`   a kind he TYPED, drawn on demand at a price, judged by
#                        HIM, reporting rates over HIS EXPECTATIONS. It is where
#                        a label comes from.
#
# One makes labels; the other consumes them. That is the whole relationship, and
# it is why this is `Lab::Realization` rather than "the generation lab": a
# universe is generated too, and `rake game:new` generates a first screen --
# *realization* is the project's own word for the one call this exercises, and
# the pairing says the relationship at a glance. A sibling for the classifier or
# the narrator would be `Lab::Classification` and `Lab::Narration`, with the same
# five nouns and the same page.
#
# THE FIVE NOUNS:
#
#   a kind         `Kind` -- what he types: a world, a name, a teaser, and the
#                  facts a real exits call would have supplied. A row.
#   an expectation columns on the kind: what he says the picks should be, as a
#                  subset of each closed list below. *Don't care* is a
#                  first-class answer and the default. Free.
#   a sample       `Sample` -- one realization of one kind, with the whole stored
#                  reading on it. A row, and the only thing here that costs
#                  money.
#   a verdict      columns on the sample: `good` / `weak` / `bad`, the aspects,
#                  the note. One click.
#   a rate         `HitRate` -- the expectation against the picks, over a kind's
#                  samples. Computed, offline, free, and RETROACTIVE: an
#                  expectation declared today scores every sample bought before
#                  it, because the picks are already on the stored row.
#
# ONE DRAW IS NOT A MEASUREMENT, and this is the one place the point is made
# rather than assumed. `EVALUATION.md` opens by saying two identical runs
# disagree by more than most claimed improvements, so the unit of JUDGEMENT here
# is the KIND and not the sample: a sample is a look, a kind is the thing that
# has a rate. `HitRate` refuses to report an unestablished one as a figure for
# the same reason `Story::Scoreboard` refuses to report an agreement below
# `MIN_VERDICTS`.
#
# AND THE LAB SUPPLIES PARAMETERS, NEVER BEHAVIOUR -- AGENTS.md's standing rule
# for a world, and here it has teeth. The prompt a sample sends is
# `Location::Generator`'s, character for character: this module stands a stub up
# and calls `#realize!`, and nothing in it writes a sentence a model reads. THERE
# IS NO PROMPT BOX IN THE LAB AND THERE MUST NEVER BE ONE -- the realization
# prompts are what `rake eval:realization` measures and what
# `Eval::Realization::BASELINE` holds to a stored set, so a second prompt source
# with no baseline would make every sample scored through it a measurement of a
# prompt no player gets.
module Lab::Realization
  # `lab_realization_kinds`, `lab_realization_samples`. Without this Rails would
  # name the tables `kinds` and `samples`: the nested-class prefix it gives
  # `Playthrough::Feedback` is only applied under a parent that is itself a
  # model, and this parent is a module.
  def self.table_name_prefix = "lab_realization_"

  # ONE PICK A REALIZATION MAKES FROM A CLOSED LIST, AND WHERE THE ANSWER LANDS.
  #
  # `values` is the list itself, read off the table that owns it rather than
  # copied -- `Location::Parameters` and `Location::Population` are the closed
  # lists the schemas are built from, so an expectation cannot allow a label the
  # model was never offered, and a label added to either arrives here with no
  # edit.
  #
  # `per_exit` is the difference between the two calls a realization makes, and
  # it is the difference that decides what a hit MEANS. The `parameters` block is
  # one answer about the building being described; `inside` and `population` are
  # answered once PER NAMED EXIT, about places that do not exist yet. So a
  # per-exit pick hits when EVERY exit's pick is in the allowed set -- set
  # membership per pick, applied to every pick that was made, which is what
  # "picking what I think it should" says when the model made four picks.
  #
  # WHAT THAT CANNOT SAY, stated because a reader will assume it: *at least one
  # of these should be a building.* That is a different claim, it is the shape
  # `Eval::Realization::Corpus`'s `expects_inside: true` label already has, and
  # the two must not be confused when a kind is promoted into a corpus case.
  Pick = Data.define(:name, :values, :per_exit) do
    def per_exit? = per_exit
    def allows?(value) = values.include?(value)
  end

  # THE SEVEN, IN THE ORDER THE CALLS MAKE THEM: the building's own five off the
  # detail call, then the two the exits call answers about somewhere else.
  #
  # THE FIVE ARE OFFERED ONLY TO A BUILDING (`Location::PlaceSchema`, reached
  # through `Location::Generator#detail_schema` off `Location#place?`), so a kind
  # with no `inside` band never has them answered and a figure over them is
  # reported unavailable rather than as a zero. `Location::Parameters`' header
  # has why there are six questions and not more, and why `deadly` will never be
  # on the danger list.
  PICKS = [
    Pick.new(name: "storeys_above", values: Location::Parameters::STOREYS_ABOVE.keys, per_exit: false),
    Pick.new(name: "storeys_below", values: Location::Parameters::STOREYS_BELOW.keys, per_exit: false),
    Pick.new(name: "danger", values: Location::Parameters::DANGER.keys, per_exit: false),
    Pick.new(name: "gradient", values: Location::Parameters::GRADIENT.keys, per_exit: false),
    Pick.new(name: "hazard", values: Location::Parameters::HAZARDS, per_exit: false),
    Pick.new(name: "inside", values: Location::Parameters::INSIDE.keys, per_exit: true),
    Pick.new(name: "population", values: Location::Population::LABELS, per_exit: true)
  ].freeze

  def self.picks = PICKS

  def self.pick(name) = PICKS.find { |entry| entry.name == name.to_s }

  # THE COLUMN AN EXPECTATION FOR ONE PICK LIVES IN.
  def self.expectation_column(pick) = :"expects_#{pick.respond_to?(:name) ? pick.name : pick}"

  # HOW MANY DRAWS OF ONE KIND BEFORE ITS RATE IS WORTH PRINTING AS A FIGURE, and
  # it is `Story::Scoreboard::MIN_VERDICTS` rather than a number of this file's
  # own: the question is the same one -- how many labelled things before a
  # per-something tally has more than a handful of cells with anything in them --
  # and a second threshold would be a second thing to argue about. Below it the
  # fraction is still printed and the words "not established" are printed with
  # it, because dressing up n=3 is the one thing an instrument must not do.
  #
  # WHAT IT COSTS TO CROSS: a sample is about a quarter of a cent
  # (`Eval::Realization::PER_CALL` and the pricing registry), so an established
  # kind is small change. The page prints the price rather than this comment
  # naming it, on the rule that a measured number lives in a stored set or a
  # test and never in prose.
  MIN_DRAWS = Story::Scoreboard::MIN_VERDICTS
end
