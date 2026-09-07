# WHICH ENDING ONE GAME REACHED, and when on the story clock.
#
# `Playthrough::Beat`'s argument one table over: a `Quest::Outcome` is the
# WORLD's -- the several ways this arc can end, written by a seed file or by
# `Quest::Generator` -- and which one happened is THIS GAME's. Two people
# playing one world reach different ends, which is the captain's *"multiple
# endings to a quest must be possible"* taken all the way down.
#
# ONE PER QUEST PER GAME, and the validation says so rather than the index: the
# index is on (playthrough, outcome), which stops the same ending being reached
# twice, and `#one_ending_per_quest` is what stops one game reaching two
# DIFFERENT endings of one arc. An arc that ended twice is a game with two
# last paragraphs.
#
# WRITTEN BY `Playthrough::Arc` AND BY NOTHING ELSE, in the same statement that
# ends the playthrough and writes the closing `Scene`. The game being over is
# never a model's decision.
class Playthrough::Ending < ApplicationRecord
  self.table_name = "playthrough_endings"

  belongs_to :playthrough
  belongs_to :quest_outcome, class_name: "Quest::Outcome"

  validates :reached_at, presence: true
  validates :quest_outcome_id, uniqueness: { scope: :playthrough_id }
  validate :outcome_belongs_to_the_story
  validate :one_ending_per_quest

  def quest = quest_outcome&.quest

  # WHAT THE PLAYER READS WHEN THE ARC IS DONE, today. The narrated version --
  # the narrator told the reached outcome, this sentence as the fallback the way
  # `Refusal#text` is one -- is `ta-quest-ending` and deliberately a slice of
  # its own: a model that refuses or truncates on the final turn of a forty-turn
  # game is the worst possible place for `BaseAgent`'s rotation to be exercised,
  # so the record lands first and the prose replaces the sentence later.
  def to_s = quest_outcome.to_s

  private

  def outcome_belongs_to_the_story
    return if quest_outcome.nil? || playthrough.nil?
    return if quest_outcome.quest.story_id == playthrough.story_id

    errors.add(:quest_outcome, "must belong to the playthrough's story")
  end

  def one_ending_per_quest
    return if quest_outcome.nil? || playthrough.nil?

    siblings = Playthrough::Ending.where(playthrough_id: playthrough_id)
                                  .where(quest_outcome: Quest::Outcome.where(quest_id: quest_outcome.quest_id))
    siblings = siblings.where.not(id: id) if persisted?
    return unless siblings.exists?

    errors.add(:quest_outcome, "is a second ending for an arc this game has already finished")
  end
end
