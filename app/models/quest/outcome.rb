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
# WHO REACHES ONE, TODAY: `Playthrough::Arc`, when the last step of the arc is
# reached, and it reaches the DEFAULT. Which of several endings a given
# playthrough gets is `ta-quest-outcomes`' question and is deliberately not
# answered here -- what this slice owes is that the shape does not foreclose it,
# and it does not: the reaching is one call with one outcome in hand.
#
# AND `is_default` IS NOT `is_good`. Nothing here says an ending is a win. A
# world may perfectly well be born with a bleak default; what the flag means is
# *the one the world was built toward*, which is the only claim the generator
# can honestly make about a sentence it wrote before anybody played.
class Quest::Outcome < ApplicationRecord
  belongs_to :quest

  validates :name, presence: true, uniqueness: { scope: :quest_id }
  validates :summary, presence: true

  scope :defaults, -> { where(is_default: true) }

  def to_s = summary.to_s
end
