# ONE BLOW LANDED IN ONE GAME, and the durable per-round record of a fight.
#
# THE CAPTAIN'S CALL C5: a round IS the turn. The player acts by typing, then
# every live foe in the room acts in `id` order (`Playthrough::Riposte`), and
# every one of those acts is a row here. Nothing else in the app records a
# round, and deliberately: a `Scene` per round would put engine copy in the
# column `Story::Audit`, `Eval::Richness` and both frozen corpora read as
# NARRATION, once per exchange. One Scene closes the fight instead
# (`Playthrough::Fight`), and these rows are what it closes.
#
# THIS GAME'S SIDE OF THE LAYER SPLIT, exactly like `Playthrough::Vitals` and
# for its reason: the world says who is hostile and how tough a body is; a game
# says who swung at whom and how much of them is left. Playthrough A killed
# Rowe, playthrough B meets him alive, and B must not be able to tell.
#
# EVERY COLUMN IS THE ENGINE'S OWN ANSWER. `damage` is one die of the attacker's
# `hit_die` (the captain's call C2: a blow always connects, no to-hit, no
# armour, no critical); `sequence` is the seed `Roll.generator` was handed, read
# off THIS TABLE's own count rather than off a counter in memory, so the same
# fight replayed a year from now throws the same dice; `round` is which turn of
# the fight it landed on, which is what the closing Scene's story time is
# `Scene::TURN_MINUTES["action"]` times. NO MODEL WRITES ONE, and there is no
# prompt that mentions any of them.
class Playthrough::Blow < ApplicationRecord
  self.table_name = "playthrough_blows"

  belongs_to :playthrough
  belongs_to :attacker, class_name: "Character"
  belongs_to :target, class_name: "Character"
  belongs_to :location
  # THE ONE SCENE THAT CLOSED THE FIGHT THIS BLOW BELONGS TO, and NIL IS THE
  # WHOLE OF "the fight is still on" -- see `Playthrough::Fight#open_blows`.
  belongs_to :scene, optional: true

  validates :damage, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :hp_after, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :round, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :sequence, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :story_timestamp, presence: true

  # Oldest first. A fight reads in the order it was fought, and `id` is the
  # order it was written in -- the same ordering `Character.present_in` and
  # `Item.lying_in` are read in, for the same stated reason.
  scope :chronological, -> { order(:id) }

  # THE ROWS NO CLOSING SCENE HAS CLAIMED: the fight that is still on.
  scope :open, -> { where(scene_id: nil) }

  # WHICH ROLL OF THIS GAME THE NEXT BLOW IS, OUT OF A RECORD.
  #
  # `Roll`'s seed is (story, playthrough, story clock, sequence) and the fourth
  # is which roll within that moment. A fight does not advance the clock until
  # it ends, so every blow of it is thrown `at` the same moment -- and if the
  # sequence came from a counter in memory, a fight replayed in a second process
  # would throw a different die. It comes from here instead: the number of blows
  # this game has already recorded.
  def self.next_sequence(playthrough) = where(playthrough: playthrough).count

  # HOW MUCH WAS LEFT OF THE BODY AFTERWARDS, as a value rather than as a live
  # read, because that is what this row is: what was true when the blow landed.
  # `Playthrough#vitals_for` is still the one reader of what is true NOW.
  def condition
    Playthrough::Vitals::Condition.new(character: target, hp: hp_after, max: target.max_hp)
  end

  def killed? = hp_after.zero?

  # For the `rake game:mechanics` read-out and for a sweep's `note:`. The
  # numbers, because a number is a fact where "badly" is a mood -- the same rule
  # `Playthrough::Vitals::Condition#in_words` is written under.
  def to_s
    "#{attacker.fullname} hit #{target.fullname} for #{damage} " \
      "(round #{round}); #{target.fullname} is #{condition.in_words}"
  end
end
