# WHETHER THE SET OF VANTAGES IS SHAPED WELL ENOUGH FOR AN OVERALL FIGURE TO
# MEAN ANYTHING -- and the refusal when it is not.
#
# THE CAPTAIN'S CALL 5 OF 2026-09-08, answered (a): *print `insides_reaching`
# beside every rate AND refuse an overall figure until the set holds both a
# "none of them" vantage and an "at least one" vantage.*
#
# WHY A REFUSAL AND NOT A WARNING. The exits prompt's own first instruction on
# this field is *"say NO INSIDE for almost all of them"*, so a model that never
# picks a building satisfies every `none of them` vantage in the set. Measured:
# the `interior-entry-before` stored set has `insides_given` at 0.000, every
# inside check clean, and no interiors anywhere in the world. A set of twenty
# open-country vantages would have read full marks for it. The dominant strategy
# is not a hypothetical here -- it is a prompt version this project has already
# shipped and measured -- so the guard is a refusal rather than a footnote.
#
# IT IS `Story::Scoreboard`'S DISCIPLINE APPLIED TO THE SHAPE OF THE SET RATHER
# THAN ITS SIZE. That class refuses to report an agreement below `MIN_VERDICTS`
# because a figure over three cells is not a figure; this refuses to report an
# alignment over one side of a two-sided question for the same reason, and both
# print the fraction and the refusal together rather than hiding either. What it
# never does is print nought: an unearned rate is worse than no rate, which is
# `Eval::Realization::Scorer`'s rule throughout.
#
# THE REFUSAL IS ABOUT THE EXPECTATIONS AND NOT ABOUT THE ANSWERS. A vantage
# counts towards a shape as soon as it DECLARES that quantifier and has a draw
# that answered -- not once it passes. A set that holds an `at least one` vantage
# failing every draw is a well-shaped set reporting bad news, which is exactly
# what it is for.
class Lab::Exits::Alignment
  # WHY THERE IS NO FIGURE, in the words the page prints. A reason and not a
  # boolean, because "there is no figure" and "here is why" are one thing to a
  # reader and two things to a caller that has to compose the sentence itself.
  Refusal = Data.define(:missing, :held) do
    def to_s
      "no overall figure yet: a set that says nothing but #{held.map(&:inspect).join(" and ")} is " \
        "satisfied by a model that never picks a building at all, so this needs a vantage expecting " \
        "#{missing.map(&:inspect).join(" and ")} beside the ones it has"
    end
  end

  attr_reader :vantages

  def initialize(vantages = nil)
    @vantages = (vantages || Lab::Exits::Vantage.all.includes(:samples, :judgements)).to_a
  end

  # THE VANTAGES WHOSE QUANTIFIER HAS A DRAW BEHIND IT, which is the only set
  # any of this is computed over.
  def scorable = @scorable ||= vantages.select { |vantage| vantage.quantifier && rate_for(vantage).answered.any? }

  # THE SHAPES THE SET ACTUALLY HOLDS, off the quantifiers he declared.
  def shapes = @shapes ||= scorable.map { |vantage| vantage.expects_inside_quantifier }.uniq

  # `Lab::Exits::BOTH_SHAPES` MINUS WHAT IT HOLDS. Empty when the set is
  # two-sided, which is the one state that has a figure.
  def missing = Lab::Exits::BOTH_SHAPES - shapes

  def both_shapes? = missing.empty?

  def refusal = both_shapes? ? nil : Refusal.new(missing: missing, held: shapes)

  # HOW MANY OF EVERY SCORABLE VANTAGE'S ANSWERED DRAWS SATISFIED ITS OWN
  # QUANTIFIER -- or nil, and then `#refusal` says why.
  #
  # POOLED OVER DRAWS AND NOT AVERAGED OVER VANTAGES, because a vantage drawn
  # thirty times and one drawn twice are not two equal opinions; `Eval::Realization::Scorer`
  # pools by opportunity for the same reason.
  def figure
    return nil unless both_shapes?

    rates = scorable.map { |vantage| rate_for(vantage).quantifier }
    Lab::Exits::HitRate::Figure.new(name: "alignment", allowed: shapes.sort.join(" / "),
                                    hits: rates.sum(&:hits), answered: rates.sum(&:answered),
                                    misses: rates.flat_map(&:misses))
  end

  # AND THE COUNTER-FIGURE OVER THE WHOLE SET, which is where it belongs: it is a
  # property of the PROMPT and not of any one place he typed, so a per-vantage
  # reading of it invites reading one vantage's open country as the game's.
  def reach
    counted = vantages.map { |vantage| rate_for(vantage).reach }

    Lab::Exits::HitRate::Reach.new(named: counted.sum(&:named), given: counted.sum(&:given),
                                   reaching: counted.sum(&:reaching))
  end

  private

  def rate_for(vantage) = (@rates ||= {})[vantage.id] ||= Lab::Exits::HitRate.new(vantage)
end
