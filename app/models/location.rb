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
  # What is lying here. An item is either in somebody's hands or in a place
  # (Item), and the ones in a place are the closed set `take` resolves
  # against -- so they belong to the durable world and go when it does.
  has_many :items, dependent: :destroy
  # Who is standing here -- the closed set `talk` resolves against
  # (`Character.present_in`). NULLIFIED rather than destroyed, which is the
  # opposite of the items above it and for a reason: a thing lying in a room
  # belongs to the room, and a person outlives the building. Destroying a
  # location leaves its cast nowhere, which is a state `Character` allows and
  # `rake game:doctor` reports.
  has_many :characters, dependent: :nullify
  has_many :playthroughs, foreign_key: :current_location_id, dependent: :nullify, inverse_of: :current_location
  has_and_belongs_to_many :connected_locations,
                          class_name: "Location",
                          join_table: "location_connections",
                          foreign_key: "location_id",
                          association_foreign_key: "connected_location_id"

  # The world's own changes that touched this place -- see WorldEvent. Declared
  # on both sides so that destroying either end clears the join rows: a Story
  # destroys its locations before its world events, and the join has a foreign
  # key on both columns.
  has_and_belongs_to_many :world_events

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
  # Places that move. A parameter of the world, read by WorldMechanic's
  # operations and by nothing else -- a mobile location is an ordinary location
  # in every other respect, and the thing that moves is the graph around it
  # rather than the place itself.
  scope :mobile, -> { where(mobile: true) }
  scope :anchored, -> { where(mobile: false) }

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

  # How long the protagonist has been away, IN STORY TIME.
  #
  # `last_protagonist_visit` holds a moment on `Story#clock`, not a wall clock,
  # and that is the whole of the fix for the defect this used to have: it read
  # `Time.current - last_protagonist_visit`, so a player who closed the tab for
  # a week and came back was told in fiction that they had been gone a week.
  # Nothing about a story's own passage of time has anything to do with when
  # somebody had a browser open.
  #
  # `now` defaults to the story's clock so any caller gets the right answer
  # without knowing that; `Scene::Generator` passes the arrival's own story
  # timestamp instead, because an arrival happens at the end of the journey
  # rather than at the moment the turn started.
  def time_since_last_visit(now = story.clock)
    return nil unless last_protagonist_visit
    return nil if now.nil?

    now - last_protagonist_visit
  end

  # `at` is story time, and it is required rather than defaulted for the reason
  # above: every caller knows which story moment the protagonist arrived at, and
  # a default would quietly reintroduce the wall clock.
  def mark_protagonist_visit!(at)
    update!(last_protagonist_visit: at)
  end
end
