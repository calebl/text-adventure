# A KIND OF PLACE HE TYPED, AND WHAT HE SAYS ITS PICKS SHOULD BE.
#
# `Lab::Realization`'s header is the design. What belongs here is the two halves
# of a kind and the line between them:
#
#   THE FACTS      a world, a name, a teaser, and the three things a real exits
#                  call would have supplied about a place it named -- the
#                  `inside` band, the `population` word, and the danger. Every
#                  one of them is a PARAMETER: the lab hands them to
#                  `Location::Generator.create_stub!`, which is the app's own one
#                  path for a room being born, and nothing here decides what any
#                  of them DOES.
#   THE EXPECTATION what he says the picks should come back as, one column per
#                   pick, each a subset of that pick's closed list.
#
# WHY IT IS "KIND" AND NOT "CASE" OR "TEST". A case is a bench word with a
# validator behind it and a room in a checked-in world file for an identity; a
# kind BECOMES a case, and the two words staying distinct is what makes that a
# promotion rather than a synonym. And a test passes or fails against a fixed
# answer, which one draw of a generative call cannot do -- calling this a test
# would invite reading a single sample as a verdict on the prompt, the exact
# error `EVALUATION.md` opens by forbidding. Both words are his own: *"a location
# of a certain kind"*, *"run through a set of samples."*
#
# THE EXPECTATION IS FREE, AND IT IS RETROACTIVE. Every pick is on the stored
# `row` of every sample already drawn (`Eval::Realization::Bench::Reading`), so
# declaring or editing one costs nothing and re-scores every sample bought
# before it. That is the opposite of the usual order and it is worth using
# deliberately: draw ten, look at them, THEN decide what you think the picks
# should have been.
#
# AND *DON'T CARE* IS THE DEFAULT AND A FIRST-CLASS ANSWER. A column left NULL
# takes this kind out of that figure's numerator AND its denominator, which is
# `Eval::Realization::Corpus`'s rule for `expects_inside` one level up, and the
# reason behind it is the same: a rate a check did not earn is worse than no
# rate. A kind that declares only `expects_hazard` has a hit rate on the hazard
# and on nothing else.
class Lab::Realization::Kind < ApplicationRecord
  has_many :samples, class_name: "Lab::Realization::Sample", foreign_key: :kind_id,
                     inverse_of: :kind, dependent: :destroy

  validates :world, presence: true, inclusion: {
    in: Eval::Realization::STORIES,
    message: "is not a world the lab has a file for (#{Eval::Realization::STORIES.join(", ")})"
  }
  validates :name, presence: true, length: { maximum: 60 }
  validates :teaser, presence: true, length: { maximum: 400 }

  # THE THREE FACTS, EACH HELD TO THE SAME CLOSED LIST THE MODEL WOULD HAVE
  # PICKED FROM. A band the table has no footprint for would give the stub an
  # extent nobody can build in, and a population word the table has no band for
  # is one `Location#population` refuses outright -- so both are refused here,
  # where there is a person to tell.
  validates :inside, inclusion: { in: Location::Parameters::INSIDE.keys }, allow_blank: true
  validates :population, inclusion: { in: Location::Population::LABELS }, allow_blank: true
  validates :danger, inclusion: { in: Location::DANGERS.keys }, allow_blank: true

  validate :expectations_are_labels_the_model_is_offered

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # WHETHER THIS KIND IS A BUILDING, asked through `Location::Parameters` rather
  # than by testing the string, because the band that means *no inside* is that
  # file's word and not this one's. It is what decides which detail schema the
  # sample's call will be sent (`Location::Generator#detail_schema`), and
  # therefore whether the five parameter picks are answered at all.
  def place? = Location::Parameters.from("inside" => inside).inside?

  # THE ALLOWED LABELS FOR ONE PICK, or nil for *don't care*. Nil and [] are
  # different states and both are reachable: nil is a column he never filled in,
  # [] is one he emptied, and an empty set allows nothing -- so it is stored as a
  # blank string and read back as no expectation, which is the only reading that
  # cannot silently make every sample a miss.
  def expects(pick)
    stored = self[Lab::Realization.expectation_column(pick)]
    labels = split(stored)

    labels.presence
  end

  # SETS OR CLEARS ONE. A list, a comma-joined string or nil all work, because
  # the page posts a checkbox group and a console posts an array. The stored
  # form is comma-joined for `Playthrough::Drift#offered`'s reason: it is read by
  # a person and grouped in Ruby, and no label in any of the closed lists holds a
  # comma.
  def declare(pick, labels)
    self[Lab::Realization.expectation_column(pick)] = Array(labels).map { |label| label.to_s.strip }
                                                                   .compact_blank.uniq.join(", ").presence
  end

  # THE PICKS HE HAS SAID ANYTHING ABOUT, in `Lab::Realization::PICKS`' order.
  def declared = Lab::Realization.picks.select { |pick| expects(pick) }

  def expectation? = declared.any?

  # WHETHER A PICK CAN EVER BE ANSWERED FOR THIS KIND, which is not the same
  # question as whether he declared it. The five parameter picks are offered only
  # to a building and the two exit picks only where an exits call is made -- and
  # a laid-out place makes none, because its ways out are its rooms'
  # (`Location::Generator#write_exits!` returns early). So a kind can carry an
  # expectation nothing will ever answer, and this is what lets the page say so
  # in words instead of printing a rate of nought.
  def answerable?(pick)
    pick.per_exit? ? !place? : place?
  end

  def unanswerable = declared.reject { |pick| answerable?(pick) }

  def hit_rate = Lab::Realization::HitRate.new(self)

  def to_s = "#{name} (#{world})"

  private

  def split(stored) = stored.to_s.split(",").map(&:strip).compact_blank

  # AN EXPECTATION MAY ONLY NAME A LABEL THE MODEL WAS OFFERED. A set holding
  # anything else is a rate that can never be earned -- the model cannot answer
  # a word its schema's enum does not carry -- and it would read on the page as
  # a prompt failing rather than as a typo.
  def expectations_are_labels_the_model_is_offered
    Lab::Realization.picks.each do |pick|
      column = Lab::Realization.expectation_column(pick)
      stray = split(self[column]) - pick.values
      next if stray.empty?

      errors.add(column, "names #{stray.map(&:inspect).join(", ")}, which is not on the list the " \
                         "model picks from (#{pick.values.join(", ")})")
    end
  end
end
