# ONE DRAW OF ONE VANTAGE: the two calls as they were made, and his judgement of
# the ANSWER as a whole.
#
# `Lab::Exits`'s header is the design. What belongs here is what a sample keeps,
# what it refuses to keep, and why its verdict is about the set of ways out while
# every judgement about a particular one lives on `Lab::Exits::Judgement`.
#
# THE ROW IS `Lab::Realization::Sample`'S ROW, EXACTLY. Both labs draw through
# `Lab::Realization::Runner`, so `row` is `Eval::Realization::Bench::Reading#to_h`
# in both -- the prompts as SENT (off the `messages` rows, never rebuilt), both
# raw answers, the facts the world held before the call, what the registries
# admitted and refused, the tokens, the latency and which model answered. So
# there is no column for the picks, the flags, the cost or the error and there
# must not be: `Eval::Realization::Scorer::Reading` reads them all back off the
# row, offline and for nothing, and a second record of any of them could disagree
# with the first.
#
# A SAMPLE OF THE EXITS PICK IS A WHOLE REALIZATION, and that is a fact about the
# app rather than a choice made here. `Location::Generator#agent` memoizes one
# conversation for both calls -- its header says so -- and the exits prompt says
# *"consistent with the description you just wrote"* twice. So there is no
# cheaper exits-only sample to buy: one would be a prompt no player gets, which
# is the trap `Lab::Realization`'s header forbids, reached by a different door.
#
# THE WORLD IT WAS DRAWN IN IS GONE. The runner stages a copy from the seed file
# inside a rolled-back transaction, so this row is the only thing that survives
# the draw, and it survives complete.
#
# HIS VERDICT IS `Playthrough::Feedback`'S THREE WORDS, read off that class
# rather than spelled again, and it is ABOUT THE SET OF WAYS OUT. That split is
# the one thing this class does differently from `Lab::Realization::Sample`, and
# the argument is that file's own, applied one level down: a realization is a
# dozen decisions in one answer, so a bare verdict cannot say which was wrong --
# and an EXITS ANSWER is up to `Location::ExitsSchema::MAX_EXITS` decisions in one
# answer, so a bare verdict on it cannot say which EXIT was wrong. What a sample's
# verdict can say is what no single exit can: whether this is the right NUMBER of
# ways out, whether a dead end had a passage invented for it, and whether there
# was a reason to prefer one over another. Every claim about a particular named
# place is a `Judgement`.
class Lab::Exits::Sample < ApplicationRecord
  belongs_to :vantage, class_name: "Lab::Exits::Vantage", foreign_key: :vantage_id,
                       inverse_of: :samples

  # ONE SPELLING OF THE LADDER, AND IT IS THE PLAY PAGE'S -- through
  # `Lab::Realization::Sample`, so all three surfaces read one table.
  VERDICTS = Lab::Realization::Sample::VERDICTS

  # WHAT ONLY THE WHOLE ANSWER CAN BE WRONG ABOUT, and each is here because no
  # judgement of one exit could carry it:
  #
  #   too_many_ways_out    the prompt says fewer is a better answer than a door
  #                        nobody needed, and the allowance is a ceiling rather
  #                        than a target. `exit_over_the_allowance` catches an
  #                        answer over the CAP; this catches one under the cap and
  #                        still too generous, which no record can read.
  #   too_few_ways_out     the mirror, and the one that costs a world its shape.
  #   invented_a_way_out   a dead end given a second exit. The prompt asks for
  #                        exactly one in that case -- *"Never invent a passage to
  #                        reach a second"* -- and `no_new_ground` is gated on a
  #                        case declaring whether the story points onward, so on a
  #                        vantage he typed this is his to say.
  #   no_reason_to_prefer  *"give the player a reason to prefer one over another"*,
  #                        which is a property of the SET of teasers and not of any
  #                        one of them.
  #   not_this_place       the whole answer is about somewhere other than the
  #                        vantage he typed. The judgement that subsumes the rest,
  #                        and nothing mechanical can make it.
  ASPECTS = %w[too_many_ways_out too_few_ways_out invented_a_way_out no_reason_to_prefer
               not_this_place].freeze

  validates :verdict, inclusion: { in: VERDICTS }, allow_nil: true
  validate :aspects_are_aspects

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :in_draw_order, -> { order(:created_at, :id) }
  scope :judged, -> { where.not(verdict: nil) }

  # THE STORED READING, WRAPPED BY THE BENCH'S OWN OBJECT -- the one reader of a
  # row in this repository, so this page cannot come to a different reading of a
  # draw from the one the bench would.
  def reading = @reading ||= Eval::Realization::Scorer::Reading.new(stored_row)

  # AND WHAT THE CHECKS MADE OF IT, computed here and never stored.
  def flags = @flags ||= Eval::Realization::Scorer.new([ stored_row ]).flags

  def failed? = reading.failed?

  def error = reading.error

  # WHETHER THE ONE CALL THIS LAB MEASURES WAS MADE AND ANSWERED AT ALL. The
  # denominator's gate for every figure, and it is asked of the SAMPLE rather
  # than of the vantage: a vantage says what it declared and a sample says what
  # was answered, and a call that failed answered nothing.
  #
  # A DRAW THAT NAMED NOTHING IS STILL NOT ANSWERED, because `min_items: 1` on the
  # schema means an empty array is a call that came back with no answer to the
  # question -- and a quantifier scored over nothing would read `none of them` as
  # satisfied by a failure.
  def answered? = !failed? && reading.asked_for_exits? && reading.exits.any?

  # EVERY PLACE THIS DRAW NAMED, with the picks it was given and what the engine
  # did with them. THE ONE READER of an exits answer in this lab -- the page, the
  # hit rate and the judgements all go through it, so none of them can disagree
  # about what a draw said.
  def named_places = @named_places ||= answered? ? reading.exits.filter_map { |exit| place_for(exit) } : []

  # THE PLACES THAT GOT A BAND THAT IS NOT `no inside`. `Scorer#inside?`'s
  # reading, and deliberately its reading rather than a test of the string: an
  # ABSENT pick is not the same thing as `no inside` -- the first is a decision
  # not made (`inside_declined`) and the second is a decision -- but both leave
  # the place with no inside, which is what the place actually became.
  def insides_given = named_places.select(&:inside?)

  # AND THE ONES WHOSE PICK THE ENGINE COULD ACTUALLY USE. The counter-figure's
  # numerator, and the captain's Call 5: a band on a place the world already held
  # is discarded by `Location::Generator#connect_exit!`, which only hands one to
  # `create_stub!` when the place does not exist. Measured at two thirds of the
  # bands given, on the stored baseline, which is why the two figures are printed
  # side by side and never averaged.
  def insides_reaching = insides_given.select(&:new_place?)

  def verdict? = verdict.present?

  def aspect_names = aspects.to_s.split(",").map(&:strip).compact_blank

  def aspect?(name) = aspect_names.include?(name.to_s)

  # RECORDS OR AMENDS THE VERDICT -- `Lab::Realization::Sample#record!`'s shape
  # and its reasoning, unchanged: he will change his mind about a draw once he has
  # seen the next one, the aspects are left alone when not supplied so a changed
  # verdict does not throw away which parts he had already said were wrong, and an
  # empty list is how they are cleared.
  def record!(verdict:, aspects: nil, note: nil)
    self.verdict = verdict.presence
    self.aspects = Array(aspects).map { |name| name.to_s.strip }.compact_blank.uniq.join(", ").presence unless aspects.nil?
    self.note = note.to_s.strip.presence unless note.nil?
    save!
    self
  end

  # ONE PLACE AN ANSWER NAMED, as the page reads it and as the rate scores it.
  #
  # `new_place?` READS THE RECORDS AND NOT THE ANSWER. `after["new_places"]` is
  # what the world held afterwards minus what it held before
  # (`Eval::Realization::Bench#after`), so it is what the engine really opened --
  # not what the model's name looked like. That matters because
  # `#connect_exit!` refuses an exit for four separate reasons before it creates
  # anything, and a reading off the answer would credit a pick that was refused.
  #
  # AND IT IS MATCHED ON `Lab::Exits.key_for`, so a place the engine created under
  # the name the model gave is recognised however the article fell. Since
  # `Location::Generator#find_location` resolves through the same key, this cannot
  # disagree with the engine about which place a name meant.
  Place = Data.define(:name, :teaser, :distance, :travel_method, :inside, :population, :new_place) do
    def key = Lab::Exits.key_for(name)

    # WHETHER A BAND WAS GIVEN AT ALL, and whether it asked for an inside. Two
    # questions, because `Location::ExitsSchema`'s `inside` is optional and an
    # absent pick is a decision NOT MADE rather than a decision to have none.
    def pick_made? = inside.present?
    def inside? = pick_made? && inside != Location::Parameters::NO_INSIDE
    def new_place? = new_place

    # WHAT THE PLACE ACTUALLY BECAME, which is what `Location::Parameters` made
    # of the answer -- so an absent pick reads as the quietest option, exactly as
    # the engine read it. Never a second interpretation of the model's silence.
    def band = Location::Parameters.from("inside" => inside).inside
  end

  private

  def place_for(exit)
    name = exit["name"].to_s.strip
    return nil if name.blank?

    Place.new(name: name, teaser: exit["teaser"], distance: exit["distance"],
              travel_method: exit["travel_method"], inside: exit["inside"].presence,
              population: exit["population"].presence, new_place: opened?(name))
  end

  def opened?(name)
    key = Lab::Exits.key_for(name)
    reading.new_places.any? { |opened| Lab::Exits.key_for(opened) == key }
  end

  # STRING KEYS, ALWAYS, whichever way the row arrived -- a row written by the
  # runner in this process carries the keys `Reading#to_h` gave it; the same row
  # read back out of the JSON column carries strings.
  def stored_row = (row.presence || {}).transform_keys(&:to_s)

  def aspects_are_aspects
    stray = aspect_names - ASPECTS
    return if stray.empty?

    errors.add(:aspects, "names #{stray.map(&:inspect).join(", ")}, which is not one of " \
                         "#{ASPECTS.join(", ")}")
  end
end
