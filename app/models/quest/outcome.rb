# ONE WAY AN ARC CAN END, AS A ROW -- and there is more than one.
#
# THE CAPTAIN'S NOTE, 2026-09-06: *"multiple endings to a quest must be
# possible. a failed quest gets stored as an event that can have future
# ramifications."* The first half is this file.
#
# WHAT IT REPLACED, and it is worth saying because it was a decided answer. The
# direction report chose `Story#conclusion`, ONE SENTENCE on the story row, and
# that is what pass one of the arc design built on. His note retires the COLUMN
# and keeps the DEFAULT: a generated world is still born with one sentence it
# was built toward (`Quest::Generator` writes it, `Quest#conclusion` reads it
# back under the decided name), and nothing anywhere may assume it is the only
# one.
#
# WHY A ROW RATHER THAN A SECOND COLUMN. Two endings would be two columns, three
# would be three, and the moment there is more than one the question "which one
# happened" needs somewhere to live that is not the world -- because it is per
# playthrough (`Playthrough::Ending`), for the reason a beat is. Rows make both
# halves ordinary.
#
# `name` IS THE NATURAL KEY and `summary` is the sentence. The key is what a
# seed file re-asserts an ending under and what the exporter writes back, which
# is `WorldSeed::Loader`'s rule for every table it touches: identity is
# something a person wrote, never an id.
#
# WHO REACHES ONE: `Playthrough::Arc`, on the turn the last step of the arc is
# reached. WHICH one it reaches is `condition`, and that is the whole of what
# this file gained for `ta-quest-outcomes`.
#
# AND `is_default` IS NOT `is_good`. Nothing here says an ending is a win. A
# world may perfectly well be born with a bleak default; what the flag means is
# *the one the world was built toward*, which is the only claim the generator
# can honestly make about a sentence it wrote before anybody played.
#
# --- WHICH OF SEVERAL, AND IT IS THE ENGINE THAT DECIDES --------------------
#
# THE RULE, AND IT IS ONE SENTENCE: **the first outcome whose condition reads
# true off this game's records wins; the default is what falling through
# means.** Ordered by id, which for a seed file is the order a person wrote the
# endings in -- so a file that wants one ending to beat another says so by
# listing it first, exactly as a `steps:` list says its own order.
#
# NOTHING ASKS A MODEL WHICH ENDING HAPPENED, on the standing constraint. Every
# condition below is a question about rows this game already wrote -- how long
# it took, and in what order it got there -- so an offline sweep can walk a
# world to a non-default ending and assert it, which is the test that makes the
# rule real rather than representable.
#
# WHY THE DEFAULT CARRIES NO CONDITION. It is the fallback, so a rule on it
# could only ever be a second way of saying the same thing or a contradiction of
# it; `#default_carries_no_condition` refuses both. Read the other way round,
# that makes a NON-default outcome with no condition an ending no path can ever
# reach -- a real defect, and one `Story::Doctor` reports
# (`outcome_nothing_can_reach`) rather than this class refusing a world over.
#
# --- AND WHAT THE WORLD DOES ABOUT IT AFTERWARDS ----------------------------
#
# *"a failed quest gets stored as an event that can have future ramifications"*,
# 2026-09-06. An outcome may carry ONE ramification: a scheduled `WorldEvent`,
# `ramification_minutes` after the ending, saying `ramification_summary`. That
# is the smallest thing a ramification can be and it is deliberately RECORD-ONLY
# -- firing it writes `fired_at` and nothing else. Nothing narrates it, nothing
# moves the graph for it, and what it is FOR is that a later reader has one
# stream to read (`WorldEvent`).
#
# THE RAMIFICATION IS THE WORLD'S AND NOT THE GAME'S -- it is written with no
# playthrough, unlike the event that records the ending itself. A game that
# reached an ending is over, its clock has stopped, and a consequence scoped to
# a stopped clock is a consequence that can never arrive: the only reading of
# *"future ramifications"* that means anything is one where the WORLD carries
# them. What one game did stays on that game's own row beside it.
class Quest::Outcome < ApplicationRecord
  # HOW AN ENDING IS SELECTED, and it is a FIXED TABLE rather than a rule
  # language -- `Quest::TRIGGERS`' argument, one table over: the direction
  # report's §12 refuses a predicate DSL, and every rule here is a question the
  # records already answer.
  #
  # The predicates themselves are `Playthrough::Arc`'s, because each of them is
  # a question about ONE GAME and this class is the world's.
  CONDITIONS = {
    # THE CLOCK. This game reached the arc's last beat more than `minutes`
    # story minutes after the story began -- `Playthrough::Arc#elapsed?`'s own
    # arithmetic, asked at the end instead of at a beat. It is the reading the
    # Iron Gate's second ending wants: you got there, and you got there late.
    "slower_than" => "reached the last beat later than `minutes` story minutes after the story began",
    # THE ROUTE. This game reached a later beat before an earlier one -- read
    # off `playthrough_beats.reached_at`, which is the record of the order this
    # player actually did it in. It takes no number, which is the whole reason
    # it is in the table: a condition is a RULE and not a threshold.
    "out_of_order" => "reached a later beat of the arc before an earlier one"
  }.freeze

  # THE ONE RULE THAT TAKES A NUMBER. Named here rather than tested against the
  # string at each call site, for `Quest::Step::TARGET_CLASSES`' reason: what a
  # kind may carry is one table and not three `if`s.
  NEEDS_MINUTES = %w[slower_than].freeze

  belongs_to :quest

  validates :name, presence: true, uniqueness: { scope: :quest_id }
  validates :summary, presence: true
  validates :condition, inclusion: { in: CONDITIONS.keys }, allow_nil: true
  # THE NUMBER GOES WITH THE RULE THAT WANTS IT AND WITH NO OTHER, which is
  # `Quest::Step`'s `minutes` validation copied deliberately: a column that
  # half-means something on the wrong kind of row is a column two readers read
  # differently.
  validates :minutes, presence: true, numericality: { only_integer: true, greater_than: 0 },
                      if: :needs_minutes?
  validates :minutes, absence: true, unless: :needs_minutes?
  validates :ramification_minutes, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :default_carries_no_condition
  validate :a_ramification_is_an_hour_and_a_sentence

  scope :defaults, -> { where(is_default: true) }
  # THE ENDINGS SOMETHING CAN SELECT, in the order a file wrote them. The one
  # reader of *"which of several"* asks for this and takes the first that holds.
  scope :conditional, -> { where.not(condition: nil).order(:id) }

  def conditional? = condition.present?

  def needs_minutes? = NEEDS_MINUTES.include?(condition)

  def slower_than? = condition == "slower_than"

  def out_of_order? = condition == "out_of_order"

  # WHETHER THIS ENDING PUTS A ROW ON THE STREAM. Both columns or neither, so
  # there is no half-written ramification for a caller to have to guess about.
  def schedules_a_ramification? = ramification_minutes.present? && ramification_summary.present?

  def to_s = summary.to_s

  private

  def default_carries_no_condition
    return unless is_default? && conditional?

    errors.add(:condition, "is the ending the world was built toward, which is what falling through means")
  end

  def a_ramification_is_an_hour_and_a_sentence
    return if ramification_minutes.blank? == ramification_summary.blank?

    errors.add(:ramification_summary, "and `ramification_minutes` are one ramification: write both or neither")
  end
end
