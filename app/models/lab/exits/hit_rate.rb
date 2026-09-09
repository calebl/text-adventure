# HOW OFTEN A VANTAGE'S EXITS CALL PICKED WHAT HE SAID IT SHOULD.
#
# `Lab::Realization::HitRate` is this file's shape and most of its reasoning, and
# every line of that reasoning still holds: computed per VANTAGE and never per
# sample, because most of the time is a rate and a rate needs repeats of the same
# thing; free, offline and RETROACTIVE, because every pick is already on every
# sample's stored row; the fraction printed and the percentage never, because
# `4 of 5` and `40 of 50` are honestly different figures.
#
# THREE FIGURES AND NOT ONE, which is what the captain's Calls 4 and 5 of
# 2026-09-08 asked for between them:
#
#   THE QUANTIFIER   over the whole answer, per draw. *None of them / at most one
#                    / at least one / every one should be a building.*
#   A PLACE          per (place, pick) he typed an expectation for, over the draws
#                    THAT NAMED THAT PLACE. Call 4c.
#   THE POPULATION   the vantage-wide set membership on the population word, which
#                    is `Lab::Realization::HitRate`'s per-exit reading unchanged:
#                    every pick that was made has to be in the set.
#
# AND THEY DO NOT FOLD TOGETHER. A quantifier figure and a per-place figure are
# claims of different arity about different subjects, and an average of them would
# be neither -- the same reason that file keeps his verdict tally out of the hit
# rate.
#
# IT READS THE PICK AND NEVER THE ROLL, which is that file's sharpest constraint
# and the standing constraint itself: a vantage that expects `a warren of rooms`
# is satisfied by the model PICKING it, whatever footprint the die then throws
# inside the band (`Location::Parameters#footprint`). Nothing here reads
# `Reading#rooms`.
#
# THE COUNTER-FIGURE IS PRINTED BESIDE EVERY RATE AND IS NOT ONE, and it is the
# captain's Call 5. `insides_reaching` is the share of named places given a band
# THAT THE ENGINE COULD USE -- a band on a place the world already held is
# discarded by `Location::Generator#connect_exit!`. Without it, every figure above
# is gameable by a model that answers `no inside` everywhere: the exits prompt's
# own first instruction on the field is *"say NO INSIDE for almost all of them"*,
# so a `none of them` vantage reads full marks for a model that has emptied the
# game of buildings. `Eval::Realization::Scorer` prints `insides_given` for
# exactly this reason and calls it THE DOMINANT-STRATEGY CHECK; this is that
# figure with the discarded picks taken out.
#
# `Lab::Exits::Alignment` IS THE OTHER HALF OF CALL 5 and lives beside this
# rather than in it: the refusal is a property of the SET of vantages, and this
# object only ever sees one.
#
# AND A LOW RATE STILL HAS TWO EXPLANATIONS. A vantage at 2 of 10 may be a
# misaligned prompt -- or an unreasonable expectation for the teaser he typed.
# Nothing here can tell those apart, which is why the page shows THE EXITS PROMPT
# AS ACTUALLY SENT beside the miss.
class Lab::Exits::HitRate
  # THE NAME OF THE FIGURE OVER EVERY DRAW RATHER THAN OVER ONE PLACE.
  EVERY = "the quantifier".freeze

  # ONE FIGURE. `answered` IS THE DENOMINATOR AND IT IS PER FIGURE, which is
  # `Story::Audit#judgeable_for`'s rule: a draw that was never asked this says
  # nothing about it, and counting it in would report a rate the figure never
  # earned. A failed call is out of every denominator.
  Figure = Data.define(:name, :allowed, :hits, :answered, :misses) do
    def judgeable? = answered.positive?
    def established? = answered >= Lab::Exits::MIN_DRAWS
    def fraction = "#{hits} of #{answered}"
    def to_s = "#{name}: #{fraction}#{established? ? "" : " -- not established"}"
  end

  # ONE DRAW'S ANSWER TO ONE FIGURE, kept beside it so a miss can be READ rather
  # than only counted. `made` is what the draw actually picked -- a list, because
  # a quantifier is about every place one answer named.
  Miss = Data.define(:sample, :made)

  attr_reader :vantage, :samples

  def initialize(vantage, samples: nil)
    @vantage = vantage
    @samples = (samples || vantage.samples.in_draw_order).to_a
  end

  def drawn = samples.size

  def failed = samples.count(&:failed?)

  # THE DRAWS THAT ANSWERED THE ONE CALL THIS LAB MEASURES. Every denominator
  # below is a subset of this.
  def answered = samples.select(&:answered?)

  # HIS OWN VERDICTS, as the two tallies they are and never folded into a rate:
  # one is about the SET of ways out and the other about a particular place, and
  # `Lab::Exits::Sample`'s header has the split.
  def verdicts = samples.filter_map(&:verdict).tally

  def place_verdicts = vantage.judgements.filter_map(&:verdict).tally

  def judged = samples.count(&:verdict?)

  # HOW MANY DIFFERENT ANSWERS THIS VANTAGE HAS GIVEN, counted on the names and
  # their bands together.
  #
  # PRINTED BESIDE THE DRAW COUNT, and it is the one figure here that is advice
  # rather than a score. Measured over the stored baseline's four repetitions,
  # three real cases returned the SAME names with the SAME picks every time while
  # four returned four different answers -- so `MIN_DRAWS` draws of a vantage that
  # has answered identically five times buys twenty-five copies of one answer. It
  # is not a rule and nothing is gated on it: it is a number that lets him stop.
  def distinct_answers
    answered.map { |sample| sample.named_places.map { |place| [ place.key, place.inside ] }.sort }.uniq.size
  end

  # THE QUANTIFIER, OVER THE DRAWS THAT ANSWERED. Nil when he has not declared
  # one -- not a figure of nought, which is `Kind#declared`'s rule.
  def quantifier
    wanted = vantage.quantifier
    return nil if wanted.nil?

    missed = answered.reject { |sample| satisfies?(sample, wanted) }

    Figure.new(name: EVERY, allowed: wanted.name, hits: answered.size - missed.size,
               answered: answered.size,
               misses: missed.map { |sample| Miss.new(sample: sample, made: sample.insides_given.map(&:name)) })
  end

  # THE POPULATION WORD, over every pick every answered draw made -- one figure
  # for the vantage, because he declares one set for it.
  # `Lab::Realization::HitRate#hit?`'s reading: a draw that gave three places the
  # word he wanted and a fourth a word he did not is a MISS, and a draw that made
  # no pick at all is a miss rather than a pass, because the population word has
  # no quietest option to fall back on.
  def population
    allowed = vantage.expects_population_labels
    return nil if allowed.nil?

    missed = answered.reject { |sample| population_hit?(sample, allowed) }

    Figure.new(name: "population", allowed: allowed.join(", "), hits: answered.size - missed.size,
               answered: answered.size,
               misses: missed.map { |sample|
                 Miss.new(sample: sample, made: sample.named_places.map { |place| place.population || "(none picked)" })
               })
  end

  # ONE FIGURE PER (PLACE, PICK) HE TYPED AN EXPECTATION FOR -- the captain's Call
  # 4c. In `Judgement#by_name` order so the page is stable between reloads.
  #
  # THE DENOMINATOR IS THE DRAWS THAT NAMED THAT PLACE, AND THAT IS THE WHOLE OF
  # WHAT MAKES THIS HONEST. `Judgement`'s header has the measurement: 26 of 66
  # place names on the stored baseline appeared in exactly one of four
  # repetitions, so scoring a typed expectation against draws that never named it
  # would report a wall of misses about a prompt that did nothing wrong. An
  # unnamed expectation is `judgeable? == false` and the page says so in words.
  def places
    @places ||= vantage.judgements.by_name.flat_map do |judgement|
      judgement.declared.map { |pick| place_figure(judgement, pick) }
    end
  end

  def place(name, pick)
    key = Lab::Exits.key_for(name)
    places.find { |figure| figure.name == "#{key}: #{pick}" }
  end

  # THE PLACES HE TYPED THAT NO DRAW HAS NAMED YET. Out of every denominator, and
  # named so the page can say WHY a figure is missing instead of printing nought.
  def unnamed
    vantage.judgements.select(&:expectation?).reject { |judgement| named?(judgement) }
  end

  # THE COUNTER-FIGURE, AND IT IS NOT A RATE HE CAN PASS. Two shares, printed
  # side by side and never averaged:
  #
  #   given     places handed a band that is not `no inside`, over places named.
  #             `Eval::Realization::Scorer`'s `insides_given` over one vantage.
  #   reaching  the same, counting only the places the ENGINE ACTUALLY OPENED --
  #             so a band on a place the world already held, which
  #             `#connect_exit!` discards, is out of the numerator.
  #
  # THE GAP BETWEEN THEM IS THE FINDING THIS LAB WAS BUILT ON: on the stored
  # baseline, 42 of 67 bands given were discarded. A vantage whose two figures are
  # far apart is a vantage whose world still holds the places its model is naming,
  # which is what the `absent` list is for.
  Reach = Data.define(:named, :given, :reaching) do
    def given_share = named.zero? ? 0.0 : given.fdiv(named)
    def reaching_share = named.zero? ? 0.0 : reaching.fdiv(named)
    def discarded = given - reaching
    def judgeable? = named.positive?
  end

  def reach
    @reach ||= Reach.new(named: answered.sum { |sample| sample.named_places.size },
                         given: answered.sum { |sample| sample.insides_given.size },
                         reaching: answered.sum { |sample| sample.insides_reaching.size })
  end

  # EVERY FIGURE HE DECLARED, in one list, for a page and a rake task to print
  # without either of them deciding the order.
  def figures = [ quantifier, population, *places ].compact

  private

  def satisfies?(sample, wanted)
    wanted.satisfied_by?(insides: sample.insides_given.size, named: sample.named_places.size)
  end

  def population_hit?(sample, allowed)
    picks = sample.named_places.map(&:population)
    return false if picks.empty?

    picks.all? { |word| word.present? && allowed.include?(word) }
  end

  def place_figure(judgement, pick)
    drew = answered.filter_map { |sample| [ sample, place_in(sample, judgement) ] if place_in(sample, judgement) }
    missed = drew.reject { |_sample, place| judgement.satisfied_by?(place) }

    # NAMED THE WAY HE TYPED IT rather than by its key. The key is how the row is
    # FOUND -- `Lab::Exits.key_for` drops the article and the case so one click
    # scores every draw however the article fell -- but it is not a place's name,
    # and a figure reading "rust market" beside an answer reading "The Rust
    # Market" would look like a figure about somewhere else.
    Figure.new(name: "#{judgement.name}: #{pick.name}", allowed: judgement.expects(pick).join(", "),
               hits: drew.size - missed.size, answered: drew.size,
               misses: missed.map { |sample, place|
                 Miss.new(sample: sample, made: [ pick.name == Lab::Exits::INSIDE ? place.band : place.population.to_s ])
               })
  end

  def place_in(sample, judgement)
    sample.named_places.find { |place| place.key == judgement.name_key }
  end

  def named?(judgement) = answered.any? { |sample| place_in(sample, judgement) }
end
