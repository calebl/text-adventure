class Scene < ApplicationRecord
  belongs_to :story
  belongs_to :location
  belongs_to :previous_scene, class_name: "Scene", optional: true
  has_one :next_scene, class_name: "Scene", foreign_key: "previous_scene_id"
  has_and_belongs_to_many :characters

  validates :description, presence: true
  validates :story_timestamp, presence: true

  after_create :mark_location_visit

  def has_next_scene?
    next_scene.present?
  end

  private

  def mark_location_visit
    location.mark_protagonist_visit!
  end
end
