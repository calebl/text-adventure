# A PLACE HE TYPED FOR THE MODEL TO NAME THE WAYS OUT OF, AND WHAT HE SAYS THOSE
# WAYS OUT SHOULD BE.
#
# `Lab::Exits`'s header is the design. What belongs here is the two halves of a
# vantage and the line between them:
#
#   THE FACTS       a world, a name, a teaser, the way in, the danger, and WHICH
#                   PLACES ARE OFF THE BOOKS. Every one is a PARAMETER: they
#                   reach `Eval::Realization::Stage` as an ad-hoc corpus case and
#                   the stub is stood up by `Location::Generator.create_stub!`,
#                   the app's own one path for a room being born. Nothing here
#                   decides what any of them DOES.
#   THE EXPECTATION the quantifier over the whole answer. The per-name half lives
#                   on `Lab::Exits::Judgement`, because it is keyed on a place and
#                   not on the vantage.
#
# WHY IT IS "VANTAGE" AND NOT "KIND". `Lab::Realization::Kind` is a kind of the
# place being WRITTEN; the place typed here is not the subject of the measurement
# at all -- it is where the model is standing when it names somewhere else. So
# the two words say which lab a row belongs to at a glance, and neither is a
# synonym for the other. The subject of a vantage's measurement has no row until
# a draw produces one, which is what `Judgement` is.
#
# IT CANNOT BE A BUILDING, and there is no column and no validation for that
# because it is unreachable rather than refused. `Location::Generator#write_exits!`
# returns early on a laid-out place -- its ways out are its rooms' -- so a vantage
# that could carry an `inside` band could silently cancel the only call this lab
# measures. `Lab::Realization::Kind#answerable?` already says the same thing from
# the other side: the two per-exit picks are answerable only where the kind is NOT
# a place.
#
# THE EXPECTATION IS FREE AND RETROACTIVE, which is `Kind`'s property and the
# reason to use it the same way: every pick is on the stored `row` of every sample
# already drawn, so declaring or editing one costs nothing and re-scores every
# draw bought before it. Draw five, look at them, THEN say what you thought the
# picks should have been.
class Lab::Exits::Vantage < ApplicationRecord
  has_many :samples, class_name: "Lab::Exits::Sample", foreign_key: :vantage_id,
                     inverse_of: :vantage, dependent: :destroy
  has_many :judgements, class_name: "Lab::Exits::Judgement", foreign_key: :vantage_id,
                        inverse_of: :vantage, dependent: :destroy

  validates :world, presence: true, inclusion: {
    in: Eval::Realization::STORIES,
    message: "is not a world the lab has a file for (#{Eval::Realization::STORIES.join(", ")})"
  }
  validates :name, presence: true, length: { maximum: 60 }
  validates :teaser, presence: true, length: { maximum: 400 }
  validates :danger, inclusion: { in: Location::DANGERS.keys }, allow_blank: true

  # THE QUANTIFIER IS HELD TO ITS OWN CLOSED LIST, for `Kind`'s reason: a word
  # the table has no rule for would be an expectation nothing could ever score,
  # and it would read on the page as a prompt failing rather than as a typo.
  validates :expects_inside_quantifier, inclusion: { in: Lab::Exits::QUANTIFIER_NAMES },
                                        allow_blank: true

  validate :expected_population_labels_are_offered

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # THE PLACES TO TAKE OFF THE BOOKS BEFORE THE CALL, one per line.
  #
  # NEWLINE-SEPARATED AND NOT COMMA-SEPARATED, which is the one place this
  # departs from `Kind`'s stored lists. That file joins on a comma and its header
  # says why it may: no label in any of the closed lists holds one. These are
  # PLACE NAMES -- the realization corpus already stages a world holding
  # `Grenn's Boarding House, Room 3` -- so a comma-joined list would split one
  # place into two names no world has, and `Eval::Realization::Stage` would
  # refuse the whole draw with a sentence about a room that was never asked for.
  def absent_names = absent.to_s.split("\n").map(&:strip).compact_blank

  # AND IT IS A LIST OF PLACES RATHER THAN A SUBTREE. Removing a place removes
  # THAT ROW: a world file that also declares rooms of it keeps them, and their
  # names stay on the prompt's reuse list, because they are ordinary locations
  # that happen to be named after their parent and nothing in the app infers a
  # tree from a name. So a vantage that wants the rooms gone names the rooms.
  # `Lab::Exits::RunnerTest` pins it, on the world that has such a place.
  #
  # AND THE VALIDATION IS DELIBERATELY NOT HERE. Whether a name is a place this
  # world holds is a question about a world file, and answering it would mean
  # loading one -- `Eval::Realization::Stage#find_room!` already asks it at
  # staging time and raises `Unstageable` with a sentence naming the world and
  # the name. Asking it twice would be two answers to what a world holds, and the
  # cheaper one would be wrong the moment a seed file changed.

  # WHAT HE SAYS THE POPULATION WORDS SHOULD BE, as a subset of the closed list,
  # or nil for *don't care* -- which is the default and a first-class answer. A
  # column left NULL takes this vantage out of that figure's numerator AND its
  # denominator, `Kind#expects`' rule and its reason: a rate a check did not earn
  # is worse than no rate.
  def expects_population_labels = split(expects_population).presence

  # SETS OR CLEARS IT. A list, a comma-joined string or nil all work, because the
  # page posts a checkbox group and a console posts an array.
  def declare_population(labels)
    self.expects_population = Array(labels).map { |label| label.to_s.strip }
                                           .compact_blank.uniq.join(", ").presence
  end

  def quantifier = Lab::Exits.quantifier(expects_inside_quantifier)

  # WHETHER HE HAS SAID ANYTHING AT ALL. A vantage with no expectation is still
  # worth drawing -- the judgements are the other half and they cost nothing to
  # write after the fact -- so this gates a figure and never a draw.
  def expectation? = quantifier.present? || expects_population_labels.present? ||
                     judgements.any?(&:expectation?)

  # THE PLACES HE HAS SAID ANYTHING ABOUT, typed in advance or judged after --
  # one row each, keyed on `Lab::Exits.key_for`.
  def judgement_for(name)
    key = Lab::Exits.key_for(name)
    return nil if key.blank?

    judgements.find { |judgement| judgement.name_key == key }
  end

  # RECORDS OR AMENDS WHAT HE SAYS ABOUT ONE PLACE, finding the row by its key or
  # creating it. The one writer of a judgement, so a name typed in advance and the
  # same name judged after a draw land on one row rather than two --
  # `Lab::Exits::Judgement`'s header has why that matters.
  def judge!(name, **attributes)
    key = Lab::Exits.key_for(name)
    raise ArgumentError, "a judgement needs a place name" if key.blank?

    judgements.find_or_initialize_by(name_key: key).tap do |judgement|
      judgement.name = name.to_s.strip if judgement.new_record?
      judgement.record!(**attributes)
    end
  end

  def hit_rate = Lab::Exits::HitRate.new(self)

  def to_s = "#{name} (#{world})"

  private

  def split(stored) = stored.to_s.split(",").map(&:strip).compact_blank

  def expected_population_labels_are_offered
    stray = split(expects_population) - Location::Population::LABELS
    return if stray.empty?

    errors.add(:expects_population,
               "names #{stray.map(&:inspect).join(", ")}, which is not on the list the model picks " \
               "from (#{Location::Population::LABELS.join(", ")})")
  end
end
