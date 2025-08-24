class Location < ApplicationRecord
  belongs_to :story
  belongs_to :parent_location, class_name: "Location", optional: true
  has_many :child_locations, class_name: "Location", foreign_key: "parent_location_id"
  has_many :scenes, dependent: :destroy
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

  validates :name, presence: true
  validates :description, presence: true
  validates :lore, presence: true

  def time_since_last_visit
    return nil unless last_protagonist_visit
    Time.current - last_protagonist_visit
  end

  def mark_protagonist_visit!
    update!(last_protagonist_visit: Time.current)
  end
end
