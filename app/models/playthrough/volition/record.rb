# WHAT ONE PERSON DECIDED TO DO ON ONE TURN OF ONE GAME, as a row.
#
# `Playthrough::Volition` is the decision; this is its receipt. They are
# separate for the reason `Playthrough::NpcAction` and `Playthrough::NpcState`
# are separate: one of them rebuilds a closed set and applies exactly one entry
# of it, and the other is a row that has to be true whoever wrote it.
#
# THIS GAME'S SIDE OF THE LAYER SPLIT, like `Playthrough::Blow` and
# `Playthrough::Toll`: the WORLD says what somebody is after
# (`characters.desire_pursuit`, written by a seed file and by the generators
# and by no typed line) and a GAME says what they did about it. Two people
# playing one world see the same person want the same thing and do different
# things with it.
#
# ONE ROW PER PRESENT CHARACTER PER PLAYED LINE, `wait` INCLUDED. A turn
# somebody stood still is a choice they made, and the point of keeping it is
# the tally: a later slice asks how often somebody has chosen what they say
# they want over what they cannot see, and a table that only recorded the
# turns something moved could not answer.
#
# EVERY COLUMN IS THE ENGINE'S OWN ANSWER. `fact` in particular is written from
# the row that moved, in the app's own voice, and no prompt mentions any of
# these columns.
class Playthrough::Volition::Record < ApplicationRecord
  self.table_name = "playthrough_volitions"

  belongs_to :playthrough
  belongs_to :character
  belongs_to :location
  # THE SCENE WHOSE PARAGRAPH TOLD THE PLAYER, exactly as on a toll. Nil is a
  # row no paragraph has carried yet, and that nil is the whole of `.untold`.
  belongs_to :scene, optional: true

  validates :chosen, presence: true
  validates :status, presence: true, inclusion: { in: Playthrough::Volition::STATUSES }
  validates :fact, presence: true
  validates :serves, presence: true, inclusion: { in: Playthrough::Volition::SERVES }
  validates :round, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validate :same_story
  validate :not_the_player

  # Oldest first, on `id`, which is the ordering every other closed set in this
  # app is read in.
  scope :chronological, -> { order(:id) }

  # THE ROWS NO PARAGRAPH HAS CARRIED YET, and only the ones that MOVED
  # something. `Playthrough::Moment` states these to the narrator once.
  #
  # `applied` ONLY, which is the one place this scope is narrower than
  # `Playthrough::Toll.untold`. A rejected pick moved nothing and a `wait`
  # moved nothing, so both are facts about the game and neither is a fact
  # about the room -- telling the narrator that three people stood still is
  # paying tokens to say nothing happened, which the prose can already see.
  scope :untold, -> { where(scene_id: nil, status: "applied") }

  scope :applied, -> { where(status: "applied") }

  private

  # `Playthrough::NpcState#same_story`'s check, and it is here for that
  # method's reason: a row naming somebody else's world is a row no reader can
  # answer from.
  def same_story
    return unless playthrough

    errors.add(:character, "must belong to this story") if character && character.story_id != playthrough.story_id
    errors.add(:location, "must belong to this story") if location && location.story_id != playthrough.story_id
  end

  # THE PLAYER DOES NOT GET ONE. The player's act is the line they typed, and a
  # volition row for the protagonist would be the engine deciding what the
  # player did. `Playthrough::Volition.run!` already skips them; this is the
  # statement said where it cannot be skipped.
  def not_the_player
    return unless character

    errors.add(:character, "must be an NPC") if character == playthrough&.character || character.is_protagonist?
  end
end
