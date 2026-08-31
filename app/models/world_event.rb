# Something the world did to itself, in story time.
#
# The audit trail rather than a message: `occurred_at` is a moment on
# `Story#clock`, `summary` says what changed in one sentence, and `locations`
# are the places it touched. Reading these back from a cold process is how the
# mechanic is checked without trusting anything in memory.
#
# DO NOT NARRATE FROM THIS LOG. Over two nights a shuffle can return a location
# to the same neighbour, so two events are honest and the player's exits are
# identical -- replaying the log would tell them the world changed when, for
# them, it did not. Narration belongs to a diff of what the player was actually
# shown, which is a separate piece of work (`ta-arrival-diff`).
class WorldEvent < ApplicationRecord
  belongs_to :world_mechanic
  belongs_to :story
  has_and_belongs_to_many :locations

  validates :occurred_at, presence: true
  validates :summary, presence: true

  scope :since, ->(at) { where(occurred_at: at..).order(:occurred_at) }
  scope :in_story_order, -> { order(:occurred_at, :id) }
end
