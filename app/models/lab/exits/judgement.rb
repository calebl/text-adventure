# ONE PLACE THIS VANTAGE NAMES, AND BOTH HALVES OF WHAT HE SAYS ABOUT IT.
#
# THE CAPTAIN'S CALL 3 OF 2026-09-08, answered (a): *one judgement row per vantage
# plus the natural key of the name the model chose, so one click scores every draw
# that produced that name.* And his Call 4, answered (c), put the other half on
# the same subject: *a quantifier PLUS a per-name expectation typed in advance.*
#
# WHY A ROW AT ALL, AND IT IS THE PROBLEM THIS LAB EXISTS INSIDE. The expectation
# is typed before the draw and the name is chosen DURING it, so he cannot expect
# "the inn should have an inside" before knowing the model will name an inn.
# `Lab::Realization::Pick`'s header raises exactly this and declines it. A row
# keyed on the place closes it from both ends: he can type a name he expects
# (Call 4c), and he can judge a name he did not (Call 3a), and either way one
# record scores every draw that ever produced that place.
#
# THE TWO HALVES, AND THEY MUST NOT BE SCORED BY ONE READER:
#
#   THE EXPECTATION  `expects_inside`, `expects_population` -- typed BEFORE, a
#                    subset of each pick's closed list, scored MECHANICALLY by
#                    set membership on every draw that named this place.
#   THE JUDGEMENT    `verdict`, `aspects`, `note` -- written AFTER, HIS click, and
#                    the only reader of everything no closed list can state.
#
# ONE ROW AND NOT TWO TABLES, and the precedent is both of the first lab's own
# models: `Lab::Realization::Kind` holds the facts and the expectation on one row
# and draws the line in its header, and `Lab::Realization::Sample` holds the
# reading and his verdict on one. Two tables keyed identically would let one
# place's expectation and one place's verdict land on different rows, and the page
# would join them on the very key that already identifies the row.
#
# THE SPLIT IS THE FIRST LAB'S RULE APPLIED TO THREE RECORDS RATHER THAN TWO --
# `Sample`'s *"Two scorers of one sample, and they must not overlap"*. What a
# closed list can score is scored mechanically, offline and for nothing; what is
# left is exactly what he clicks. So `verdict` never grades the band and
# `expects_inside` never grades the teaser.
#
# `name_key` IS THE IDENTITY AND `name` IS ONLY FOR PRINTING. `Lab::Exits.key_for`
# is `WorldSeed.natural_key` -- the repo's one spelling of "the same name written
# differently" -- so a place he typed as `the rust market` and a place the model
# named `Rust Market` are one row. Keyed any narrower, this instrument would file
# `Causeway Court` and `The Causeway Court` as two places, which is precisely the
# defect `Location::Generator#find_location` was widened to close, reappearing in
# the tool built to watch for it.
#
# A TYPED NAME THAT NEVER COMES BACK IS OUT OF THE DENOMINATOR AND NOT A MISS,
# and this is the ONE RULE THAT MAKES CALL 4c HONEST. Measured on the stored
# baseline: 26 of 66 place names appeared in exactly one of four repetitions, so a
# reading that scored an unnamed expectation as a failure would report a wall of
# misses about a prompt that did nothing wrong. It is `Kind#expects`' *don't care*
# rule -- a NULL takes a figure's numerator AND its denominator -- applied per
# place rather than per pick, and `HitRate` is where it is enforced.
class Lab::Exits::Judgement < ApplicationRecord
  belongs_to :vantage, class_name: "Lab::Exits::Vantage", foreign_key: :vantage_id,
                       inverse_of: :judgements

  VERDICTS = Lab::Exits::Sample::VERDICTS

  # WHAT NO CLOSED LIST CAN STATE ABOUT ONE NAMED PLACE, and each is here because
  # a record check either cannot read it or can only be GRADED by it:
  #
  #   inside_wrong      whether THIS teaser describes a building somebody goes in
  #                     at a door. The whole reason the lab exists, and the one
  #                     thing no record will ever answer.
  #   band_wrong        it should have an inside, but not that size. Separate from
  #                     the above because the two fail differently: measured, the
  #                     largest of the three bands was picked more often than the
  #                     other two together, which is a calibration fault and not a
  #                     yes/no one.
  #   population_wrong  whether the word matches what the place is FOR, which is
  #                     the sentence the prompt actually asks for.
  #   distance_wrong    whether the distance or the travel method matches the
  #                     teaser the model itself wrote. Both are closed lists, so
  #                     an expectation COULD be typed for them -- and must not be:
  #                     he holds no prior about how far away a place he did not
  #                     name should be, so their rightness is relative to the
  #                     answer and therefore a judgement.
  #   teaser_wrong      whether the one line gives a reason to walk that way.
  #   name_wrong        whether it is the kind of name this world uses. Prose in
  #                     one field, `Eval::Realization::UNAVAILABLE_TO_A_REALIZATION`'s
  #                     refusal one level down.
  #   shouldnt_exist    this place has no business in this world. The judgement
  #                     that subsumes the rest.
  #
  # OFFERED ON A `weak` OR A `bad` AND NEVER REQUIRED -- `Playthrough::Feedback`'s
  # rule that a form which needs filling in will not get filled in. A `good` is one
  # click and nothing else.
  ASPECTS = %w[inside_wrong band_wrong population_wrong distance_wrong teaser_wrong name_wrong
               shouldnt_exist].freeze

  validates :name, presence: true, length: { maximum: 120 }
  validates :name_key, presence: true, uniqueness: { scope: :vantage_id }
  validates :verdict, inclusion: { in: VERDICTS }, allow_nil: true
  validate :aspects_are_aspects
  validate :expectations_are_labels_the_model_is_offered

  before_validation :key_the_name

  scope :by_name, -> { order(:name_key, :id) }
  scope :judged, -> { where.not(verdict: nil) }

  # THE ALLOWED LABELS FOR ONE PICK, or nil for *don't care*. Nil and [] are
  # different states and both are reachable -- nil is a column he never filled in,
  # [] is one he emptied -- so an empty set is stored as blank and read back as no
  # expectation, which is the only reading that cannot silently make every draw a
  # miss. `Kind#expects`' rule, unchanged.
  def expects(pick)
    split(self[column_for(pick)]).presence
  end

  def declare(pick, labels)
    self[column_for(pick)] = Array(labels).map { |label| label.to_s.strip }
                                          .compact_blank.uniq.join(", ").presence
  end

  # THE PICKS HE HAS TYPED AN EXPECTATION FOR, in `Lab::Exits::PICKS`' order.
  def declared = Lab::Exits.picks.select { |pick| expects(pick) }

  def expectation? = declared.any?

  def verdict? = verdict.present?

  def aspect_names = aspects.to_s.split(",").map(&:strip).compact_blank

  def aspect?(name) = aspect_names.include?(name.to_s)

  # WHETHER THIS ROW EXISTS ONLY BECAUSE HE TYPED IT, which is what lets the page
  # say *"you expected this place and no draw has named it yet"* rather than
  # printing a rate over nothing. Not a column: a row with an expectation and no
  # verdict is exactly that state, and a boolean beside it could disagree.
  def unmet? = expectation? && !verdict?

  # WHETHER ONE DRAW'S PICKS FOR THIS PLACE FALL INSIDE WHAT HE TYPED. Set
  # membership on every pick he declared, which for a per-exit pick is one value
  # per named place -- so this is plain equality against his subset.
  #
  # A PLACE THIS DRAW DID NOT NAME IS NOT ASKED, and the caller checks that
  # (`HitRate`). A place it DID name with no pick made is a MISS for the population
  # word and a hit for `no inside`, which is `Location::Parameters`' reading of an
  # absent field and not a second one: silence about the band means the place has
  # no inside, and there is no word for *I would rather not say how populated this
  # is*.
  def satisfied_by?(place)
    declared.all? do |pick|
      allowed = expects(pick)
      value = pick.name == Lab::Exits::INSIDE ? place.band : place.population

      value.present? && allowed.include?(value)
    end
  end

  # RECORDS OR AMENDS EITHER HALF, and the halves do not touch each other.
  #
  # AN ARGUMENT NOT SUPPLIED IS LEFT ALONE, which is what makes one endpoint
  # serve both the typing and the judging: posting a verdict does not clear an
  # expectation he typed a week ago, and posting an expectation does not clear a
  # verdict. `Playthrough::Feedback.record`'s rule, applied to a row with two
  # authors' worth of state on it.
  def record!(verdict: nil, aspects: nil, note: nil, expects: nil)
    self.verdict = verdict.presence unless verdict.nil?
    self.aspects = Array(aspects).map { |name| name.to_s.strip }.compact_blank.uniq.join(", ").presence unless aspects.nil?
    self.note = note.to_s.strip.presence unless note.nil?
    (expects || {}).each { |pick, labels| declare(pick, labels) }
    save!
    self
  end

  def to_s = name

  private

  def column_for(pick) = Lab::Realization.expectation_column(pick)

  def split(stored) = stored.to_s.split(",").map(&:strip).compact_blank

  def key_the_name
    self.name = name.to_s.strip.presence
    self.name_key = Lab::Exits.key_for(name)
  end

  def aspects_are_aspects
    stray = aspect_names - ASPECTS
    return if stray.empty?

    errors.add(:aspects, "names #{stray.map(&:inspect).join(", ")}, which is not one of " \
                         "#{ASPECTS.join(", ")}")
  end

  # AN EXPECTATION MAY ONLY NAME A LABEL THE MODEL WAS OFFERED -- `Kind`'s
  # validation and its reason: a set holding anything else is a rate that can
  # never be earned, and it would read on the page as a prompt failing rather
  # than as a typo.
  def expectations_are_labels_the_model_is_offered
    Lab::Exits.picks.each do |pick|
      stray = split(self[column_for(pick)]) - pick.values
      next if stray.empty?

      errors.add(column_for(pick),
                 "names #{stray.map(&:inspect).join(", ")}, which is not on the list the model picks " \
                 "from (#{pick.values.join(", ")})")
    end
  end
end
