class Scene < ApplicationRecord
  belongs_to :story
  belongs_to :location
  belongs_to :previous_scene, class_name: "Scene", optional: true
  has_one :next_scene, class_name: "Scene", foreign_key: "previous_scene_id"
  has_and_belongs_to_many :characters
  # What a character thought and felt during this moment. Written by the talk
  # branch of the game loop; nullified rather than destroyed because an
  # Interaction belongs to its character first and the scene only optionally.
  has_many :interactions, dependent: :nullify
  has_many :playthroughs, foreign_key: :current_scene_id, dependent: :nullify, inverse_of: :current_scene

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
