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
# --- AND THE SECOND CLAUSE: A ROW MAY BE ABOUT THE FUTURE -------------------
#
# *"some events will need to happen at a particular time, like if we have story
# where a bomb is going to go off or a volcano is going to explode 1 week in the
# future."* An event today is a thing that HAS happened; a bomb a week out is a
# row saying a thing WILL. So there are THREE moments on this table and each one
# is a different question:
#
#   occurred_at    WHEN THE ROW WAS RECORDED, on the story clock. Every row has
#                  one. On a row about the past it is also when the thing
#                  happened, which is why nothing about the old rows moved.
#   scheduled_for  WHEN THE THING IS DUE. NULL on a row about the past, which
#                  is what makes `#scheduled?` the whole of the distinction.
#   fired_at       WHEN THE ENGINE FIRED IT. Null until it does.
#
# `fired_at` IS A MOMENT AND NOT A BOOLEAN, deliberately. The engine fires a due
# row on the story's own clock and the clock only moves when somebody plays, so
# a row due at midnight fires at the first turn past midnight and the gap
# between the two is real. A flag would throw away the only record of it.
#
# WHO FIRES ONE: `Story#catch_up_world!`, in the same call and on the same clock
# `WorldMechanic` already catches up on -- the captain's own reading of Call 8,
# *"the engine fires a due event when the clock reaches it"*. One place, one
# clock, one answer to *has the world caught up*.
#
# A FUTURE CATASTROPHE IS AN ORDINARY SCHEDULED ROW. There is no volcano table
# and no bomb mechanic: a world file writes a `schedule:` block
# (`WorldSeed::Loader`), a quest outcome writes its ramification
# (`Playthrough::Arc`), and both are rows here that the same reader fires.
#
# AND THE NARRATOR IS TOLD A SCHEDULED EVENT ONLY WHEN IT HAPPENS -- which today
# means not at all, because nothing narrates from this log (above) and firing a
# row writes `fired_at` and nothing else. Telling a model about a bomb a week
# out invites it to foreshadow an explosion the engine has not recorded, which
# is Call 4's reasoning applied to the clock instead of to the quest.
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
  # A WORLD FILE, WHICH IS ONLY EVER A SCHEDULE. The log of what happened is not
  # seed data and is never exported (`WorldSeed::Exporter`); a statement about
  # what WILL happen is -- *the tide is over the low door in three quarters of
  # an hour* is a fact the world was written with, in `WorldMechanic`'s own
  # doctrine: the file supplies the hour and the sentence, the engine supplies
  # the firing. Spelled the way `Quest::ORIGINS` spells the same writer.
  SEEDED = "seeded".freeze
  SOURCES = [ WORLD_MECHANIC, QUEST, SEEDED ].freeze

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
  # A ROW CANNOT HAVE FIRED IF IT WAS NEVER DUE. `fired_at` is the answer to
  # *when did the engine reach this row's hour*, and a row with no hour has
  # none -- so this is the same statement `Quest::Step`'s `minutes` validation
  # makes: a column that only means something for one kind of row is refused on
  # every other kind, rather than left to be read as a half-meaning.
  # `Story::Doctor` reports one that got in anyway.
  validates :fired_at, absence: true, unless: :scheduled?

  scope :since, ->(at) { where(occurred_at: at..).order(:occurred_at) }
  scope :in_story_order, -> { order(:occurred_at, :id) }
  # WHAT THE WORLD ITSELF DID, which is the set every reader before the arc was
  # asking for -- so `WorldMechanic`'s own callers keep exactly the answer they
  # had, and a failed arc does not turn up in a count of what a law has done.
  scope :of_the_world, -> { where(playthrough_id: nil) }
  scope :from_mechanics, -> { where(source: WORLD_MECHANIC) }
  scope :from_quests, -> { where(source: QUEST) }
  # THE OTHER HALF OF THE SENTENCE IN THE HEADER: what has happened in this
  # GAME is the world's rows plus this playthrough's own, and never another
  # playthrough's. A reader that forgets the second half shows one player a
  # failure that is not theirs, which is the exact thing `playthrough_id` was
  # added to prevent.
  scope :for_a_game, ->(playthrough) { where(playthrough_id: [ nil, playthrough&.id ]) }
  scope :from_a_world_file, -> { where(source: SEEDED) }
  # A ROW ABOUT THE FUTURE THAT HAS NOT ARRIVED YET, and its opposite. Every
  # reader of *"what has happened"* wants `happened`; only the firing pass and
  # the doctor want `pending`. They are scopes rather than a filter in Ruby
  # because the firing pass runs on every turn of every game.
  scope :pending, -> { where.not(scheduled_for: nil).where(fired_at: nil) }
  scope :happened, -> { where(scheduled_for: nil).or(where.not(fired_at: nil)) }
  # EVERY UNFIRED ROW THIS STORY HAS REACHED THE HOUR OF, oldest first -- which
  # is exactly `WorldMechanic#pending_boundaries` one table over, and answered
  # by the same arithmetic on two datetimes rather than by a timer.
  scope :due_by, ->(at) { pending.where(scheduled_for: ..at).order(:scheduled_for, :id) }

  def from_a_mechanic? = source == WORLD_MECHANIC

  def from_a_quest? = source == QUEST

  def scheduled? = scheduled_for.present?

  def fired? = fired_at.present?

  # A THING THAT IS STILL GOING TO HAPPEN. The one predicate every reader of
  # this stream has to ask before treating a row as history.
  def pending? = scheduled? && !fired?

  # WHEN THE THING ACTUALLY HAPPENED, or nil for one that has not yet. Three
  # columns, one question -- so a reader asking *"did anything happen between
  # these two turns"* (`Story::Audit#still?`) cannot accidentally count a bomb
  # that is still ticking as an event that went off.
  def happened_at = pending? ? nil : (fired_at || occurred_at)

  # THE HOUR REACHED, WRITTEN ONCE. `at` is the story clock's reading at the
  # moment the engine noticed, which is at or after `scheduled_for` -- see the
  # header for why the gap is kept rather than collapsed to a flag.
  #
  # Idempotent: a row that has already fired keeps the moment it fired at, so a
  # catch-up run twice cannot re-date a bomb.
  def fire!(at:)
    return self unless pending?

    update!(fired_at: at)
    self
  end

  # WHAT WROTE THE ROW, for a reader that shows the stream to a person. A
  # mechanic has a name somebody chose; an arc has no row of its own to name,
  # so it is described. Never `world_mechanic.name` at a call site --
  # the association is nullable and a caller that forgets raises on the one
  # kind of row that has no mechanic.
  def writer = world_mechanic&.name || "the story's arc"
end
