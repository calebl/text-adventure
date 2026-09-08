# THE EXITS LAB: ONE PLACE HE TYPED, THE MODEL ASKED WHAT LIES BEYOND IT, AND
# EVERY PICK IT MADE ABOUT A PLACE THAT DOES NOT EXIST YET JUDGED AGAINST WHAT HE
# SAID IT SHOULD BE.
#
# THE CAPTAIN'S ASK, 2026-09-08, verbatim: *"I want to keep the existing lab
# as-is and create a new one that exists to cover the space where the model picks
# on the exits call. I want it to work in the same as the existing one."*
#
# WHICH SPACE, EXACTLY, AND WHY THE FIRST LAB CANNOT COVER IT. When a place names
# its ways out, the one call that gives each exit a name, a teaser, a distance and
# a travel method also picks whether that named place HAS AN INSIDE, from the
# closed list in `Location::Parameters` (`Location::ExitsSchema`, the `inside`
# field). That is the model's first decision about a place, made before the place
# exists. `Lab::Realization` starts after it: a kind is typed straight into a
# world and HIS `inside` band is handed to `Location::Generator.create_stub!` as a
# parameter, so no neighbouring exits call ever named it. The first lab measures
# what the engine does with a band; this one measures where the band comes from.
#
# A LAB IS NOT A BENCH, and `Lab::Realization`'s header owns that distinction.
# This is its sibling and the relationship is unchanged: a bench is a fixed
# corpus judged by record checks and replayed offline for nothing; a lab is
# something he typed, drawn at a price, judged by HIM. One makes labels, the
# other consumes them.
#
# WHAT IT SHARES WITH THE FIRST LAB, WHICH IS ALMOST EVERYTHING:
# `Lab::Exits::Runner` subclasses `Lab::Realization::Runner` so a draw is the
# same draw; `PICKS` below is read off `Lab::Realization::PICKS` rather than
# respelled; `MIN_DRAWS`, the verdict ladder, the staging, the rollback, the arm
# pinning, the `debug` layout and `app/views/lab/_styles.html.erb` are all taken
# as they stand. Only three things are its own, and each is one of his answers.
#
# THE FIVE NOUNS, AND THE ONE THE FIRST LAB DOES NOT HAVE:
#
#   a vantage    `Vantage` -- what he types: a world, a name, a teaser, the way
#                in, and WHICH PLACES ARE OFF THE BOOKS. A row.
#   an expectation two shapes, both free and both retroactive: a QUANTIFIER over
#                the whole answer on the vantage, and a per-name expectation on a
#                `Judgement` row.
#   a sample     `Sample` -- one realization, with the whole stored reading on it.
#                The only thing here that costs money.
#   a judgement  `Judgement` -- one row per place this vantage names, carrying his
#                verdict on that place's picks. THE NOUN THE FIRST LAB HAS NO NEED
#                OF, and the reason is `Judgement`'s header.
#   a rate       `HitRate` -- the expectation against the picks, over a vantage's
#                samples. Computed, offline, free and retroactive.
#
# WHY THE `absent` LIST IS THE LOAD-BEARING INPUT, and it is the finding that
# shaped the whole design (`data/ta-exits-lab-scout/report.md` section 2.2, four
# bought draws). A vantage typed into a world that still holds unrealized stubs
# has its exits call name THOSE -- correctly, because the prompt lists them and
# asks for reuse -- and `Location::Generator#connect_exit!` only hands the
# `inside` band to `create_stub!` for a place that does not already exist. So
# every pick is thrown away and the lab measures nothing, silently, while still
# printing picks and rates. Taking places off the books is what gives the model a
# reason to invent, and `Eval::Realization::Stage`'s `absent` surgery already does
# it -- so a vantage carries the list and the staging is borrowed unchanged.
#
# IT DOES NOT STOP THE MODEL NAMING THE PLACE, and that is the knob working
# rather than failing: the universe and the preface still describe it, so the
# name arrives as NEW GROUND, the pick reaches the world, and what he is looking
# at is a real decision. `iron-gate-surface` in the realization corpus is exactly
# this shape.
#
# AND THE LAB SUPPLIES PARAMETERS, NEVER BEHAVIOUR -- AGENTS.md's standing rule,
# and it binds here for the reason it binds on the first lab: the prompt a sample
# sends is `Location::Generator`'s, character for character. THERE IS NO PROMPT
# BOX AND THERE MUST NEVER BE ONE. `Location::ExitsSchema`'s field descriptions
# and the exits instruction block are what `rake eval:realization` measures and
# what `Eval::Realization::BASELINE` holds to a stored set, and EVALUATION.md
# names *"a schema's field descriptions"* among the things a baseline is required
# before touching. This lab exists to make that prompt judgeable, so it is the one
# thing it may not edit.
module Lab::Exits
  # `lab_exits_vantages`, `lab_exits_samples`, `lab_exits_judgements`.
  # `Lab::Realization.table_name_prefix`'s reason unchanged: the nested-class
  # prefix Rails gives `Playthrough::Feedback` is only applied under a parent
  # that is itself a model, and this parent is a module.
  def self.table_name_prefix = "lab_exits_"

  # THE TWO PICKS THE EXITS CALL MAKES ABOUT A PLACE THAT DOES NOT EXIST YET,
  # READ OFF `Lab::Realization::PICKS` AND NOT RESPELLED. They are the same two
  # questions asked by the same schema of the same closed lists, so a second
  # spelling would be a second answer to what the model was offered -- and a
  # label added to `Location::Parameters::INSIDE` or `Location::Population::LABELS`
  # has to arrive in both labs with no edit. `Pick#per_exit?` is true of both,
  # which is what makes them this lab's subject and not the first lab's.
  PICKS = %w[inside population].map { |name| Lab::Realization.pick(name) }.freeze

  def self.picks = PICKS

  def self.pick(name) = PICKS.find { |entry| entry.name == name.to_s }

  # THE PICK THE QUANTIFIER IS ABOUT. Named rather than left as `PICKS.first`,
  # because "the inside pick" appears in three files and an index would be the
  # kind of thing that survives a reorder and stops being true.
  INSIDE = "inside".freeze

  # HOW MANY OF THE PLACES ONE ANSWER NAMED SHOULD HAVE AN INSIDE -- the captain's
  # Call 4 of 2026-09-08, answered (c): a quantifier over the whole answer, PLUS
  # the per-name expectations on the `Judgement` rows.
  #
  # WHY A QUANTIFIER AT ALL, AND IT IS THE GAP THE FIRST LAB'S OWN HEADER NAMES
  # AND DECLINES. `Lab::Realization::Pick` scores a per-exit pick by set
  # membership applied to EVERY pick that was made, and says so: *"WHAT THAT
  # CANNOT SAY, stated because a reader will assume it: at least one of these
  # should be a building."* That is the claim a person actually holds about a
  # place before seeing it -- *a stretch of road in open country: none of them; a
  # city lane: at least one* -- and it is the shape `Eval::Realization::Corpus`'s
  # `expects_inside` label already has one level down, which is where a scored
  # vantage is promoted to.
  #
  # IT IS BEHAVIOUR AND SO IT IS A TABLE IN CODE. AGENTS.md's rule -- a world
  # supplies parameters, never behaviour -- so the vantage row stores the WORD
  # and what the word means lives here.
  #
  # AND EVERY ONE OF THEM IS GAMEABLE BY A MODEL THAT NEVER PICKS A BUILDING,
  # which is why `HitRate#insides_reaching` is printed beside every figure and
  # why `Alignment` refuses a set that holds only one side. The prompt's own
  # first instruction on this field is *"say NO INSIDE for almost all of them"*,
  # so a set of nothing but `none of them` vantages reads full marks for a model
  # that has emptied the game of buildings -- measured: the
  # `interior-entry-before` stored set has `insides_given` at 0.000 with every
  # inside check clean.
  Quantifier = Data.define(:name, :allows) do
    # `insides` is how many of the named places were given a band that is not
    # `no inside`; `named` is how many places the answer named at all.
    def satisfied_by?(insides:, named:) = allows.call(insides, named)

    def to_s = name
  end

  QUANTIFIERS = [
    Quantifier.new(name: "none of them", allows: ->(insides, _named) { insides.zero? }),
    Quantifier.new(name: "at most one", allows: ->(insides, _named) { insides <= 1 }),
    Quantifier.new(name: "at least one", allows: ->(insides, _named) { insides.positive? }),
    # `named.positive?` is not pedantry: an answer that named nothing has every
    # one of nothing given an inside, and calling that a hit would score a
    # failed call as agreement.
    Quantifier.new(name: "every one", allows: ->(insides, named) { named.positive? && insides == named })
  ].freeze

  QUANTIFIER_NAMES = QUANTIFIERS.map(&:name).freeze

  def self.quantifier(name) = QUANTIFIERS.find { |entry| entry.name == name.to_s }

  # THE TWO SHAPES A SET OF VANTAGES HAS TO HOLD BEFORE AN OVERALL FIGURE MEANS
  # ANYTHING -- `Alignment`'s refusal, named here because both ends read it.
  BOTH_SHAPES = [ "none of them", "at least one" ].freeze

  # HOW MANY DRAWS OF ONE VANTAGE BEFORE ITS RATE IS WORTH PRINTING AS A FIGURE.
  # `Lab::Realization::MIN_DRAWS` and not a number of this file's own, for that
  # file's reason one step further out: it is already
  # `Story::Scoreboard::MIN_VERDICTS`, and a third threshold would be a third
  # thing to argue about.
  MIN_DRAWS = Lab::Realization::MIN_DRAWS

  # THE IDENTITY OF A PLACE, AND THERE IS ONE ANSWER TO IT IN THIS REPOSITORY.
  # `WorldSeed.natural_key` drops case, runs of whitespace and a leading article
  # and goes no wider; `Story::Doctor#duplicate_locations` groups on it and, since
  # `Location::Generator#find_location` resolves through it, so does the engine
  # when it decides whether an exits answer named a place the world already had.
  # A judgement keyed any narrower would file `Causeway Court` and
  # `The Causeway Court` as two places -- which is the defect that fix closed,
  # reappearing in the instrument built to watch for it.
  def self.key_for(name) = WorldSeed.natural_key(name)

  # WHETHER TWO NAMES ARE ONE PLACE. The predicate form, for readers that have a
  # name rather than a key.
  def self.same_place?(left, right) = key_for(left) == key_for(right) && key_for(left).present?
end
