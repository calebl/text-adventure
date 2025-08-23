class Interaction < ApplicationRecord
  belongs_to :character
  belongs_to :scene
  belongs_to :location

  validates :pre_thought, presence: true
  validates :pre_feeling, presence: true
  validates :action, presence: true
  validates :post_feeling, presence: true
  validates :post_thought, presence: true

  scope :chronological, -> { order(:created_at) }
  scope :for_character, ->(character) { where(character: character) }

  def completed?
    inner_resolution.present?
  end

  def character_name
    character.fullname
  end
end
