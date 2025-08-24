class LocationConnection < ApplicationRecord
  belongs_to :location
  belongs_to :connected_location, class_name: "Location"

  validates :distance, presence: true
  validates :time_to_travel, presence: true
  validates :travel_method, presence: true
  validates :location_id, uniqueness: { scope: :connected_location_id }

  scope :from_location, ->(location) { where(location: location) }
  scope :to_location, ->(location) { where(connected_location: location) }
end
