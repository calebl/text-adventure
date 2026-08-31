# One direction of an edge in the world graph.
#
# `distance` and `travel_method` are picked from fixed tables rather than
# written as prose, for two reasons that both showed up in real generated data:
#
#   1. A 60-character cap on a free-text field truncates mid-word. A real row
#      read "Just below the window, maybe a minute's climb down the rains" --
#      exactly 60 characters, with "rainspout" cut in half.
#   2. Connections are written in both directions from one answer, so a
#      directional phrase is wrong on the way back. "Climb down the drainpipe
#      to the lane below" was stored as the way *up* as well. Every value in
#      TRAVEL_METHODS is direction-neutral, so the same value is correct both
#      ways and the bug cannot recur.
#
# `time_to_travel` is derived from the other two rather than decided at all.
class LocationConnection < ApplicationRecord
  # How far, in nominal minutes of walking. The labels are what a player reads,
  # so they are phrases rather than symbols.
  DISTANCES = {
    "adjacent" => 1,
    "a short walk" => 5,
    "across the district" => 20,
    "a long journey" => 120,
    "days away" => 2880
  }.freeze

  # How you get there, as a multiplier on the walking time. Direction-neutral
  # on purpose -- see the class comment.
  TRAVEL_METHODS = {
    "walking" => 1.0,
    "taking stairs" => 1.5,
    "climbing" => 3.0,
    "crawling" => 4.0,
    "swimming" => 2.5,
    "rowing" => 0.8,
    "riding" => 0.4
  }.freeze

  belongs_to :location
  belongs_to :connected_location, class_name: "Location"

  before_validation :derive_time_to_travel

  validates :distance, presence: true, inclusion: { in: DISTANCES.keys }
  validates :travel_method, presence: true, inclusion: { in: TRAVEL_METHODS.keys }
  validates :time_to_travel, presence: true
  validates :location_id, uniqueness: { scope: :connected_location_id }

  scope :from_location, ->(location) { where(location: location) }
  scope :to_location, ->(location) { where(connected_location: location) }

  # Minutes for a distance travelled by a method, or nil if either is not one
  # of the known values -- validation reports that, this does not guess.
  def self.travel_minutes(distance, travel_method)
    base = DISTANCES[distance]
    factor = TRAVEL_METHODS[travel_method]
    return nil if base.nil? || factor.nil?

    base * factor
  end

  # A short human phrase for a number of minutes. Deliberately vague: the game
  # never does arithmetic on this, it only reads it out.
  def self.humanize_minutes(minutes)
    return nil if minutes.nil?

    case minutes
    when ...1 then "under a minute"
    when 1...2 then "about a minute"
    when 2...60 then "about #{minutes.round} minutes"
    when 60...120 then "about an hour"
    when 120...1440 then "about #{(minutes / 60.0).round} hours"
    when 1440...2880 then "about a day"
    else "about #{(minutes / 1440.0).round} days"
    end
  end

  private

  def derive_time_to_travel
    self.time_to_travel = self.class.humanize_minutes(
      self.class.travel_minutes(distance, travel_method)
    )
  end
end
