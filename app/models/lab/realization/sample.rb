# ONE DRAW OF ONE KIND: the two calls as they were made, and his judgement of
# what came back.
#
# `Lab::Realization`'s header is the design. What belongs here is what a sample
# KEEPS and what it refuses to keep.
#
# IT KEEPS THE WHOLE STORED READING AND NOTHING DERIVED FROM IT. `row` is
# `Eval::Realization::Bench::Reading#to_h` -- the prompts as SENT (off the
# `messages` rows, never rebuilt), both raw answers, the facts the world held
# before the call, what the registries admitted and refused, the tokens, the
# latency, and which model answered. Everything a reader of this page wants is
# read back off it by `Eval::Realization::Scorer::Reading`, offline and for
# nothing -- so there is no column for the picks, the flags, the cost or the
# error, and there must not be: a second record of any of them could disagree
# with the first, and the first is the one the bench reads.
#
# THE WORLD IT WAS DRAWN IN IS GONE. `Lab::Realization::Runner` stages a copy of
# the world from its seed file inside a rolled-back transaction, which is the
# only way to realize a room in one of the captain's universes without leaving a
# room in it (`Eval::Realization::Stage`'s three guarantees). So this row is the
# only thing that survives the draw, and it survives complete.
#
# HIS VERDICT IS `Playthrough::Feedback`'S THREE WORDS, read off that class
# rather than spelled again: `good` / `weak` / `bad`, ordinal, one word each. Its
# header carries the argument against a fourth -- *"a fourth button is a decision
# to make instead of a judgement to record"* -- and it holds here unchanged.
#
# AND THE ASPECTS ARE WHAT A BARE VERDICT CANNOT SAY. A narration turn is one
# passage, so a bare verdict on one is a complete judgement; a realization is a
# dozen decisions in one answer, and a `bad` with nothing else on it cannot say
# which of them was wrong and therefore cannot grade any particular check. So a
# `weak` or a `bad` is OFFERED six checkboxes, ZERO of which is a complete
# answer -- the rule `Playthrough::Feedback`'s header sets for the optional note,
# applied to the aspects: a form that needs filling in will not get filled in.
# A `good` is one click and nothing else.
#
# THERE ARE SIX AND NOT TEN, and the four that are missing did not get dropped:
# they RETIRED INTO THE EXPECTATION. The `inside`, `storeys`, `danger` and
# `hazard` picks all come from closed lists, so `Lab::Realization::HitRate`
# scores them mechanically, by equality, offline, free, and without him clicking
# anything. What is left is exactly what no closed list can state. Two scorers of
# one sample, and they must not overlap.
class Lab::Realization::Sample < ApplicationRecord
  belongs_to :kind, class_name: "Lab::Realization::Kind", foreign_key: :kind_id, inverse_of: :samples

  # ONE SPELLING OF THE LADDER, AND IT IS THE PLAY PAGE'S. He already judges
  # turns with these three words and the debug view already colours them; a
  # second table here would be a second ordering to keep in step.
  VERDICTS = Playthrough::Feedback::VERDICTS

  # WHAT NO CLOSED LIST CAN STATE, and each one is here because a record check
  # either cannot read it or can only be GRADED by it:
  #
  #   not_the_place_i_meant  the whole realization missed the teaser. The one
  #                          judgement that subsumes every other and that nothing
  #                          mechanical can make.
  #   prose                  whether the description is worth reading.
  #                          `Eval::Realization::UNAVAILABLE_TO_A_REALIZATION`
  #                          names this a refusal rather than a gap -- there is
  #                          no deterministic reader of it and a judge model
  #                          would be a second model to keep honest. His verdict
  #                          is the only ground truth there is or will be.
  #   people / things        whether these are the RIGHT people and things, which
  #                          is a different question from whether the count was
  #                          legal. The allowance checks answer the second.
  #   exits                  whether these are the right ways out. Same split.
  #   name                   a room's name is prose in one field.
  ASPECTS = %w[not_the_place_i_meant prose people things exits name].freeze

  validates :verdict, inclusion: { in: VERDICTS }, allow_nil: true
  validate :aspects_are_aspects

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :in_draw_order, -> { order(:created_at, :id) }
  scope :judged, -> { where.not(verdict: nil) }

  # THE STORED READING, WRAPPED BY THE BENCH'S OWN OBJECT. The one reader of a
  # row in this repository -- `Eval::Realization::Result`, the board, the
  # comparison and the offline rescorer all go through it -- so the page cannot
  # come to a different reading of a sample from the one the bench would.
  def reading = @reading ||= Eval::Realization::Scorer::Reading.new(stored_row)

  # AND WHAT THE CHECKS MADE OF IT, computed here and never stored. One row's
  # flags, each with the evidence sentence a reader needs to see whether the
  # check was right (`Eval::Realization::Scorer::Flag`).
  def flags = @flags ||= scorer.flags

  # THE BENCH'S SCORER OVER THIS ONE ROW, memoized so the three questions below
  # cost one pass between them. One row, so every count it answers is nought or
  # one.
  def scorer = @scorer ||= Eval::Realization::Scorer.new([ stored_row ])

  # WHETHER THIS ROW GAVE ONE CHECK ANYTHING TO READ. The denominator's gate on
  # the agreement side, and it is the SCORER's own
  # (`Eval::Realization::Scorer#judgeable_for`) rather than a second reading of
  # the same row -- a check unavailable here is unavailable on the bench.
  def judges?(code) = scorer.judgeable_for(code).positive?

  def flagged?(code) = flags.any? { |flag| flag.code == code.to_sym }

  def failed? = reading.failed?

  def error = reading.error

  # THE PICK THIS SAMPLE MADE FOR ONE FIELD, read THROUGH the engine's own
  # interpreter of the answer and never off the raw JSON. `Location::Parameters`
  # is what `Location::Generator` handed the answer to, so an absent pick reads
  # as the quietest option -- which is what the place actually became. A second
  # reading here would be a second answer to what the model's silence meant.
  #
  # A LIST, ALWAYS, because the two exit picks are answered once per named exit
  # and the five parameter picks once per sample. Empty when the call that would
  # have answered was never made.
  def picks_for(pick)
    return [] if failed?
    return exit_picks(pick) if pick.per_exit?
    return [] unless reading.parameters_asked?

    [ Location::Parameters.from(reading.parameters).public_send(pick.name) ]
  end

  # WHETHER THE CALL THAT ANSWERS THIS PICK WAS MADE AT ALL. The denominator's
  # gate, and it is asked of the SAMPLE rather than of the kind: a kind says what
  # it declared and a sample says what was answered, and a call that failed
  # answered nothing. `Eval::Realization::Scorer`'s rule throughout -- a rate a
  # check never earned is worse than no rate.
  def answered?(pick)
    return false if failed?
    return reading.asked_for_exits? && reading.exits.any? if pick.per_exit?

    reading.parameters_asked?
  end

  def verdict? = verdict.present?

  def aspect_names = aspects.to_s.split(",").map(&:strip).compact_blank

  def aspect?(name) = aspect_names.include?(name.to_s)

  # RECORDS OR AMENDS THE VERDICT, and the amendment is the point:
  # `Playthrough::Feedback.record`'s reason unchanged -- he will change his mind
  # about a sample once he has seen the next one. Clearing is amendment's other
  # half, which is a verdict of nil.
  #
  # THE ASPECTS ARE LEFT ALONE WHEN NOT SUPPLIED, so clicking a different verdict
  # does not silently throw away which parts he had already said were wrong; an
  # empty list is how they are cleared. Same for the note, and same rule as
  # `Playthrough::Feedback.record`.
  def record!(verdict:, aspects: nil, note: nil)
    self.verdict = verdict.presence
    self.aspects = Array(aspects).map { |name| name.to_s.strip }.compact_blank.uniq.join(", ").presence unless aspects.nil?
    self.note = note.to_s.strip.presence unless note.nil?
    save!
    self
  end

  private

  # STRING KEYS, ALWAYS, whichever way the row arrived. A row written by the
  # runner in this process carries the keys `Reading#to_h` gave it; the same row
  # read back out of the JSON column carries strings. One shape has to serve
  # both, which is `Eval::Realization::Bench::Pass#rows`' rule.
  def stored_row = (row.presence || {}).transform_keys(&:to_s)

  def exit_picks(pick)
    return [] unless reading.asked_for_exits?

    reading.exits.map do |exit|
      next Location::Parameters.from("inside" => exit["inside"]).inside if pick.name == "inside"

      # AND THE POPULATION WORD HAS NO QUIETEST OPTION TO FALL BACK ON, which is
      # `Location::ExitsSchema`'s note on why it is the one required field of the
      # two: nil on the column means NOBODY PICKED, and the engine rolls a word
      # when somebody walks in. So a declined pick is reported as nil and counts
      # as a miss against any expectation -- there is no word for *I would rather
      # not say*, and `population_declined` is the check that measures it.
      exit["population"].presence
    end
  end

  def aspects_are_aspects
    stray = aspect_names - ASPECTS
    return if stray.empty?

    errors.add(:aspects, "names #{stray.map(&:inspect).join(", ")}, which is not one of " \
                         "#{ASPECTS.join(", ")}")
  end
end
