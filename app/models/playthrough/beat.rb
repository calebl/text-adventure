# ONE BEAT OF THE ARC, REACHED, IN ONE GAME.
#
# THE `Item` LAYER SPLIT APPLIED TO PROGRESS, and it is the same argument one
# table over: a `Quest::Step` is the WORLD's -- what this world's arc asks for,
# written by a seed file or by `Quest::Generator` and touched by no player ever
# -- and whether somebody has reached it is THIS GAME's. Two people playing one
# world reach the beats in their own order, at their own moment on the story
# clock, so a `quest_steps.reached_at` column would be one player's progress
# stored on the world exactly the way a shared inventory was.
#
# WRITTEN ONCE, BY ONE WRITER. `Playthrough::Arc` is the only thing in the app
# that creates one, and it creates one when a trigger predicate reads true off
# the records after a turn the engine PLAYED. Not off narration, not off a tool
# call, and not on a refused line -- a refused line writes nothing, so it cannot
# reach a beat (the captain's ruling of 2026-09-04).
#
# `reached_at` IS STORY TIME (`Playthrough#story_now`) and never the wall clock,
# for `Playthrough#end!`'s reason: a beat re-derived from a backup would
# otherwise be dated to whenever somebody opened the backup.
#
# THE UNIQUE INDEX IS THE IDEMPOTENCE. A `reach_location` beat is true on every
# turn the player stands in the room, and the arc is evaluated on every turn, so
# without it a look in the right room would write a row a turn. The FIRST moment
# is the one that is true, so the row is created once and never updated.
class Playthrough::Beat < ApplicationRecord
  self.table_name = "playthrough_beats"

  belongs_to :playthrough
  belongs_to :quest_step, class_name: "Quest::Step"

  validates :reached_at, presence: true
  validates :quest_step_id, uniqueness: { scope: :playthrough_id }
  validate :step_belongs_to_the_story

  scope :in_story_order, -> { order(:reached_at, :id) }

  # A row per (playthrough, step) and nothing else, so a caller that asks twice
  # in one turn gets the moment the beat actually happened rather than the
  # moment it asked.
  def self.reach!(playthrough, step, at:)
    find_or_create_by!(playthrough: playthrough, quest_step: step) { |beat| beat.reached_at = at }
  end

  private

  # The same statement `Playthrough::Vitals#character_belongs_to_the_story`
  # makes: a beat pointing at another story's arc would silently mix two worlds.
  def step_belongs_to_the_story
    return if quest_step.nil? || playthrough.nil?
    return if quest_step.quest.story_id == playthrough.story_id

    errors.add(:quest_step, "must belong to the playthrough's story")
  end
end
