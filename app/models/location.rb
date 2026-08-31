class Location < ApplicationRecord
  belongs_to :story
  # Containment. NOTHING SETS THIS YET: Location::Generator creates every stub
  # from an exit, which says where you can walk, not what is inside what. The
  # generator used to put "contained within: X" into the detail prompt on a
  # branch that could never be taken; that branch is gone. The association
  # stays because the column and the design do, but a caller has to write it
  # before any prompt can read it.
  belongs_to :parent_location, class_name: "Location", optional: true
  has_many :child_locations, class_name: "Location", foreign_key: "parent_location_id"
  has_many :scenes, dependent: :destroy
  has_many :playthroughs, foreign_key: :current_location_id, dependent: :nullify, inverse_of: :current_location
  has_and_belongs_to_many :connected_locations,
                          class_name: "Location",
                          join_table: "location_connections",
                          foreign_key: "location_id",
                          association_foreign_key: "connected_location_id"

  has_and_belongs_to_many :inverse_connected_locations,
                          class_name: "Location",
                          join_table: "location_connections",
                          foreign_key: "connected_location_id",
                          association_foreign_key: "location_id"

  # A location is generated in two steps, so it exists in two states. A *stub*
  # is a name and a one-line teaser: it is created the moment a neighbouring
  # location names it as an exit, so "three doors lead out" always corresponds
  # to three real records the player can walk into. A *realized* location has
  # been written out in full and is what the player actually reads.
  #
  # Scopes are off because Rails would define a class method named `stub`,
  # which shadows minitest's Object#stub across every test in the suite.
  enum :detail_level, { stub: "stub", realized: "realized" },
       default: :stub, validate: true, scopes: false

  scope :stubs, -> { where(detail_level: :stub) }
  scope :realized, -> { where(detail_level: :realized) }

  validates :name, presence: true
  # A stub has neither yet -- that is the point of a stub. A realized location
  # without them is still broken, so the requirement holds where it matters.
  validates :description, presence: true, if: :realized?
  validates :lore, presence: true, if: :realized?

  # The places you can walk to from here. Connections are stored directionally
  # but written in both directions when a location is realized, so this one
  # association is the whole exit list.
  def exits
    connected_locations
  end

  def time_since_last_visit
    return nil unless last_protagonist_visit
    Time.current - last_protagonist_visit
  end

  def mark_protagonist_visit!
    update!(last_protagonist_visit: Time.current)
  end
end
