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

  # WHAT WALKING THIS WAY COSTS, and THIS IS THE FIRST MECHANIC THAT WANTS THE
  # DIRECTED EDGE. A door is two rows (the ruling of 2026-09-03, and the class
  # comment above says why every OTHER value on them is direction-neutral), so a
  # hazard written on one row is ONE-WAY BY CONSTRUCTION and nothing has to
  # enforce it: the drop through the hulk's hatch hurts and the climb back out
  # onto the rock does not.
  #
  # A ONE-WAY HAZARD IS NOT A ONE-WAY EXIT. Both rows still exist and both still
  # lead both ways -- `Location#exits` is unchanged and the door is as walkable
  # backwards as it ever was. Only the COST differs. One-way exits (a fall, a
  # chute you cannot climb) stay unsupported and deliberately deferred; this
  # does not reopen them and is written down here so nobody reads it as though
  # it had.
  #
  # `save` is the ability, or nil for a thing nobody can dodge. There is no
  # `when:` on this table and there does not need to be: an edge has exactly one
  # moment, which is when it is walked (`Playthrough::Hazards#on_arrival!`).
  HAZARDS = {
    "drop" => { save: :dexterity, words: "the way down is further than it looks from the top" },
    "undertow" => { save: :strength, words: "the water pulls at you the whole way across" }
  }.freeze

  belongs_to :location
  belongs_to :connected_location, class_name: "Location"
  # EVERY TOLL PAID WALKING THIS WAY. NULLIFIED rather than destroyed, and it is
  # the one place the two hazard tables answer differently: a doorway can be
  # deleted and rewritten by `WorldMechanic::ShuffleConnections` in the ordinary
  # course of a world moving, and losing what the drop cost somebody last week
  # because the city rearranged itself would be losing the measurement to keep
  # the map. The toll still names the room it was paid arriving in, which is
  # what `Playthrough::Toll#where_it_was` falls back to.
  has_many :tolls, class_name: "Playthrough::Toll", dependent: :nullify,
                   inverse_of: :location_connection

  before_validation :derive_time_to_travel

  validates :distance, presence: true, inclusion: { in: DISTANCES.keys }
  validates :travel_method, presence: true, inclusion: { in: TRAVEL_METHODS.keys }
  validates :time_to_travel, presence: true
  validates :location_id, uniqueness: { scope: :connected_location_id }

  validates :hazard, inclusion: { in: HAZARDS.keys }, allow_nil: true
  validates :hazard_die, inclusion: { in: Location::HAZARD_DICE }, allow_nil: true
  # Half a hazard is refused here for the reason `Location#a_hazard_is_whole`
  # refuses it one table over: a key with no die is a column that looks as
  # though it said something and did not.
  validate :a_hazard_is_whole

  scope :from_location, ->(location) { where(location: location) }
  scope :to_location, ->(location) { where(connected_location: location) }
  scope :hazardous, -> { where.not(hazard: nil) }

  # THE ONE ROW THAT IS WALKED when somebody goes from `origin` to
  # `destination`, and it is one row and never the pair -- which is the whole
  # point of the hazard being on it.
  def self.walked(origin, destination)
    return nil if origin.nil? || destination.nil?

    from_location(origin).to_location(destination).first
  end

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

  # WHAT WALKING THIS WAY DOES TO YOU, as the table entry rather than as the
  # key -- the one reader, so nothing else fetches out of `HAZARDS`. Nil for the
  # ordinary doorway, which is every doorway in every world but one.
  def hazard_entry = HAZARDS[hazard]

  def hazardous? = !hazard_entry.nil? && hazard_die.present?

  private

  def a_hazard_is_whole
    return if hazard.blank? == hazard_die.blank?

    errors.add(:hazard, "and hazard_die go together: a hazard is a key and a die, or it is neither")
  end

  def derive_time_to_travel
    self.time_to_travel = self.class.humanize_minutes(
      self.class.travel_minutes(distance, travel_method)
    )
  end
end
