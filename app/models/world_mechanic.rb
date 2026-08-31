# One law of a world that the APP enforces, on the story's own clock.
#
# THE POINT OF THIS CLASS is what it does not do: it never asks a model
# anything, and nothing has to remember it. `kind` and `cadence` are keys into
# fixed tables in this file, each naming a Ruby operation over records --
# exactly the shape `LocationConnection::DISTANCES` and `::TRAVEL_METHODS`
# already have. A generated or hand-seeded world supplies *parameters* (which
# places move, how often, and the in-fiction reason) and never behaviour. So a
# mechanic holds whether or not any narrator recalls it, and it costs zero
# tokens per turn.
#
# THE SCHEDULE IS STORY TIME. `last_run_at` is a column holding a moment on
# `Story#clock`, so catching up is arithmetic on two datetimes read out of the
# database: no timer, no job, no scheduler, nothing in memory. A process that
# was down for a week catches up on the next turn, and never re-runs a night it
# already ran. That is what makes this dependable rather than suggested.
#
# A cadence is a BOUNDARY IN THE STORY'S DAY, not an interval from
# `start_time`. The Lunar Cartographer opens at 23:00; with "nightly" as a
# 1,440-minute interval from the start, its first night would fire 23 hours
# late. `pending_boundaries` therefore snaps to multiples of the period from
# the epoch, which for 1,440 minutes is midnight UTC.
class WorldMechanic < ApplicationRecord
  # The whole catalogue. One entry, and adding a second one is adding a class
  # here -- not a field a model gets to fill in.
  KINDS = { "shuffle_connections" => "WorldMechanic::ShuffleConnections" }.freeze

  # `period` is how often, in story minutes. `at` offsets the boundary within
  # the period, in minutes -- 0 means the period's own edge, which is midnight
  # UTC for `nightly` because the epoch is a midnight.
  CADENCES = {
    "hourly" => { period: 60, at: 0 },
    "nightly" => { period: 1440, at: 0 },
    "weekly" => { period: 10_080, at: 0 }
  }.freeze

  belongs_to :story
  has_many :world_events, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :story_id }
  validates :kind, presence: true, inclusion: { in: KINDS.keys }
  validates :cadence, presence: true, inclusion: { in: CADENCES.keys }

  # Every mechanic in a story, caught up to the story's clock. THIS is the
  # per-turn entry point: one `SELECT MAX(story_timestamp)` plus one row read
  # per mechanic when nothing is due, which is almost every turn.
  def self.catch_up_story!(story)
    now = story.clock

    story.world_mechanics.order(:id).flat_map { |mechanic| mechanic.catch_up!(now) }
  end

  def operation
    KINDS.fetch(kind).constantize.new(self)
  end

  def interval_minutes
    CADENCES.fetch(cadence).fetch(:period)
  end

  def offset_minutes
    CADENCES.fetch(cadence).fetch(:at)
  end

  # The story times at which this should have fired, from the last run up to
  # and including `now`. Plain arithmetic, and the only reason it is a method
  # rather than a line is the boundary snapping described in the class comment.
  def pending_boundaries(now)
    from = last_run_at || story.start_time
    return [] if now.nil? || from.nil? || now <= from

    period = interval_minutes * 60
    offset = offset_minutes * 60
    first = Time.at(((from.to_i - offset) / period + 1) * period + offset).utc

    boundaries = []
    at = first
    while at <= now
      boundaries << at
      at += period
    end
    boundaries
  end

  # Runs every boundary the story has passed, oldest first, and returns the
  # WorldEvents that came of it.
  #
  # One transaction PER BOUNDARY, each stamping `last_run_at`, so a failure on
  # the third night of a catch-up keeps the first two rather than replaying
  # them. Idempotent for the same reason: `last_run_at` is a column, so a
  # restart mid-playthrough resumes and never re-runs a night it already ran.
  def catch_up!(now)
    pending_boundaries(now).filter_map do |at|
      transaction do
        event = operation.run!(at)
        update!(last_run_at: at)
        event
      end
    end
  end
end
