# HOW OFTEN A KIND'S PICKS CAME BACK THE WAY HE SAID THEY SHOULD.
#
# THE CLAUSE THIS FILE EXISTS FOR, the captain, 2026-09-07: *"I want to make sure
# it is picking what I think it should MOST OF THE TIME."* Most of the time is a
# rate; a rate needs a denominator; a denominator needs repeats OF THE SAME KIND.
# So this is computed per KIND and never per sample -- a sample is a look, a kind
# is the thing that has a rate.
#
# FREE, OFFLINE AND RETROACTIVE. Every pick is already on every sample's stored
# row, so this touches no model and no world: declaring an expectation costs
# nothing, EDITING one re-computes rather than re-buys, and an expectation
# written today scores every sample drawn before it existed.
#
# IT READS THE PICK AND NEVER THE ROLL, and that is the sharpest constraint here.
# `Eval::Realization::Scorer` states it about its own checks and the reason is
# the standing constraint itself: *"Danger, gradient and hazard are RATES -- a die
# decides each room -- so a place that picked `dangerous` and rolled quiet rooms
# was not narrowed, it was unlucky, and flagging that would be flagging the
# dice."* A kind that expects `danger: dangerous` is satisfied by the model
# PICKING `dangerous`, whatever the per-room ladder then throws
# (`Location::Parameters#danger_for`), and a `flooded` place with one dry room is
# `HAZARD_SHARE` working rather than the prompt failing. So every figure below
# reads `Scorer::Reading#parameters` and the exits answer; nothing reads
# `#rooms`. The layout is still rendered on the page -- it is most of what he
# asked to see -- and it is not scored against him.
#
# THE FRACTION IS PRINTED AND THE PERCENTAGE IS NOT. `4 of 5` and `40 of 50` are
# honestly different figures and a percentage hides which one is on the screen.
# `#established?` is false below `Lab::Realization::MIN_DRAWS` and the page says
# so in words, which is `Story::Scoreboard`'s discipline for exactly the same
# reason.
#
# AND A LOW RATE HAS TWO EXPLANATIONS, NOT ONE. A kind sitting at 2 of 10 may be
# a misaligned prompt -- or an unreasonable expectation for the teaser he typed.
# Nothing here can tell those apart, which is why the page shows THE PROMPT AS
# ACTUALLY SENT beside the miss: reading "asked for a cellar" in the prompt and
# seeing `none` come back is a diagnosis, and a bare 2 of 10 is only a complaint.
class Lab::Realization::HitRate
  # ONE PICK'S RATE OVER ONE KIND'S SAMPLES.
  #
  # `answered` IS THE DENOMINATOR AND IT IS PER PICK, which is
  # `Story::Audit#judgeable_for`'s rule: a sample whose call was never offered
  # this pick says nothing about it, and counting it in would report a rate the
  # figure never earned. A failed call is out of every denominator, for the same
  # reason `Eval::Realization::Scorer#readings` rejects one.
  # `pick` AND `allowed` ARE NIL ON EXACTLY ONE FIGURE -- `#overall`, which is
  # every declared pick at once and therefore belongs to no single one of them.
  # Named here rather than left to the reader because a `#name` that reached
  # through the nil would raise on the one figure a console or a rake task is
  # most likely to print.
  EVERY = "every declared pick".freeze

  Figure = Data.define(:pick, :allowed, :hits, :answered, :misses) do
    def name = pick&.name || EVERY
    def judgeable? = answered.positive?
    def established? = answered >= Lab::Realization::MIN_DRAWS
    def fraction = "#{hits} of #{answered}"
    def to_s = "#{name}: #{fraction}#{established? ? "" : " -- not established"}"
  end

  # ONE SAMPLE'S ANSWER TO ONE PICK, kept beside the figure so a miss can be
  # read rather than only counted. `made` is the picks the model actually made
  # for that field -- a list, because the two exit picks are answered once per
  # named exit.
  Miss = Data.define(:sample, :made)

  attr_reader :kind, :samples

  def initialize(kind, samples: nil)
    @kind = kind
    @samples = (samples || kind.samples.in_draw_order).to_a
  end

  def drawn = samples.size

  def failed = samples.count(&:failed?)

  # HIS OWN VERDICTS OVER THIS KIND, as the tally they are. Not folded into the
  # hit rate and never comparable with it: one says whether the picks were what
  # he asked for and the other says whether the room was any good, and a combined
  # number would be neither. `Lab::Realization::Sample`'s header has the split.
  def verdicts = samples.filter_map(&:verdict).tally

  def judged = samples.count(&:verdict?)

  # ONE FIGURE PER PICK HE DECLARED, in `Lab::Realization::PICKS`' order. A pick
  # he said nothing about has no figure at all -- not a figure of nought.
  def figures = @figures ||= kind.declared.map { |pick| figure_for(pick) }

  def figure(name) = figures.find { |entry| entry.name == name.to_s }

  # AND THE ONE FIGURE OVER ALL OF THEM: how often EVERY pick he declared came
  # back the way he said it should.
  #
  # ITS DENOMINATOR IS THE SAMPLES WHERE EVERY DECLARED PICK WAS ANSWERED, which
  # is stricter than the union and is the only reading that needs no caveat: "all
  # of them hit" is not a claim anybody can make about a sample that was never
  # asked half of them. A kind whose expectation spans both calls -- a building's
  # parameters and its exits' insides -- can therefore have no such sample, and
  # this reads as unjudgeable while the per-pick figures above it still read.
  # `Kind#unanswerable` is what lets the page say WHY in words.
  def overall
    wanted = kind.declared
    return nil if wanted.empty?

    scorable = samples.select { |sample| wanted.all? { |pick| sample.answered?(pick) } }
    hits = scorable.count { |sample| wanted.all? { |pick| hit?(sample, pick) } }

    Figure.new(pick: nil, allowed: nil, hits: hits, answered: scorable.size, misses: [])
  end

  private

  def figure_for(pick)
    allowed = kind.expects(pick)
    answered = samples.select { |sample| sample.answered?(pick) }
    missed = answered.reject { |sample| hit?(sample, pick) }

    Figure.new(pick: pick, allowed: allowed, hits: answered.size - missed.size, answered: answered.size,
               misses: missed.map { |sample| Miss.new(sample: sample, made: sample.picks_for(pick)) })
  end

  # SET MEMBERSHIP, AND EVERY PICK THAT WAS MADE HAS TO BE IN THE SET. For the
  # five parameter picks there is exactly one, so this is plain equality against
  # his subset. For the two the exits call answers there is one per named exit,
  # and a sample that gave three exits the word he wanted and the fourth a word
  # he did not is a MISS -- `Lab::Realization::Pick`'s header says what that
  # reading can and cannot express, and which corpus label is the other shape.
  #
  # A SAMPLE THAT MADE NO PICK AT ALL IS A MISS AND NOT A PASS, which only
  # happens for the population word: it is the one field with no quietest option
  # to fall back on, so an absent one is `population_declined` and the room got
  # nothing he asked for.
  def hit?(sample, pick)
    made = sample.picks_for(pick)
    return false if made.empty?

    allowed = kind.expects(pick) || []
    made.all? { |value| value.present? && allowed.include?(value) }
  end
end
