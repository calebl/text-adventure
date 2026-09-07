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
#
# --- ONE STREAM, AND `source` IS WHAT MADE IT ONE --------------------------
#
# THE CAPTAIN'S CALL 8, 2026-09-06: *"one event stream could work but some
# events will need to happen at a particular time, like if we have story where a
# bomb is going to go off or a volcano is going to explode 1 week in the
# future."* The first clause is this file today. A failed quest is not a
# mechanic, so `world_mechanic_id` went NULLABLE and every row says which writer
# wrote it -- because *"future ramifications"* means something later has to read
# ONE stream, not two.
#
# WHAT THE SECOND CLAUSE NEEDS AND THIS DELIBERATELY DOES NOT ADD: a SCHEDULED
# story-clock time, distinct from `occurred_at`. An event today is a thing that
# HAS happened; a bomb a week out is a row saying a thing WILL. That is two
# timestamps meaning two different things, plus an engine that fires a due row
# on the same tick `WorldMechanic` already runs on, plus a doctor finding for a
# due time that passed with nothing fired. It is `ta-quest-outcomes`, it is
# bigger than the failure case that prompted it, and it is worth building
# deliberately rather than as a column somebody added in passing. NOTHING HERE
# FORECLOSES IT: a nullable `scheduled_for` and a reader on the mechanic tick is
# an additive migration over this shape.
#
# --- WHY A FAILURE NAMES ITS PLAYTHROUGH -----------------------------------
#
# `playthrough_id` IS NULL FOR EVERY EVENT THE WORLD CAUSED, which is every
# mechanic's, and set for every event ONE GAME caused, which today is a failed
# arc. The split is `Item`'s and `Playthrough::Vitals`': the world moves for
# everybody, but one player dying two rooms short of the prince did not happen
# to anybody else, and a story-level row saying it did would tell a second
# player about a failure that is not theirs. A reader that wants *"what has
# happened in this WORLD"* asks for the rows with no playthrough; one that wants
# *"what has happened in this GAME"* asks for the world's plus its own.
class WorldEvent < ApplicationRecord
  # WHO WROTE THE ROW. A closed list for `Location::HAZARDS`' reason: a source
  # outside it is a writer nothing downstream can read, and a reader of one
  # stream has to be able to tell a fired law from a failed arc.
  WORLD_MECHANIC = "world_mechanic".freeze
  QUEST = "quest".freeze
  SOURCES = [ WORLD_MECHANIC, QUEST ].freeze

  # NULLABLE BECAUSE A FAILED QUEST IS NOT A MECHANIC, and required of a
  # mechanic's own row for the reason it always was: an event attributed to no
  # law is an event nothing can explain.
  belongs_to :world_mechanic, optional: true
  belongs_to :story
  # OPTIONAL, AND NULL IS THE ORDINARY ANSWER -- see the header. A
  # `Playthrough` destroys these with itself, on `Playthrough`'s own doctrine:
  # what happened to ONE GAME is that player's progress, and a world nobody is
  # playing has no arc anybody failed.
  belongs_to :playthrough, optional: true
  has_and_belongs_to_many :locations

  validates :occurred_at, presence: true
  validates :summary, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :world_mechanic, presence: true, if: :from_a_mechanic?

  scope :since, ->(at) { where(occurred_at: at..).order(:occurred_at) }
  scope :in_story_order, -> { order(:occurred_at, :id) }
  # WHAT THE WORLD ITSELF DID, which is the set every reader before the arc was
  # asking for -- so `WorldMechanic`'s own callers keep exactly the answer they
  # had, and a failed arc does not turn up in a count of what a law has done.
  scope :of_the_world, -> { where(playthrough_id: nil) }
  scope :from_mechanics, -> { where(source: WORLD_MECHANIC) }
  scope :from_quests, -> { where(source: QUEST) }

  def from_a_mechanic? = source == WORLD_MECHANIC

  def from_a_quest? = source == QUEST
end
