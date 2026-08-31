class Story < ApplicationRecord
  belongs_to :universe
  has_many :characters, dependent: :destroy
  has_many :locations, dependent: :destroy
  has_many :scenes, dependent: :destroy
  # Interactions hang off characters; destroying the story destroys the
  # characters, which take their own interactions with them.
  has_many :interactions, through: :characters
  has_many :playthroughs, dependent: :destroy
  has_one :protagonist, -> { where(is_protagonist: true) }, class_name: "Character", inverse_of: :story

  validates :title, presence: true
  validates :genre, presence: true
  validates :preface, presence: true
  validates :summary, presence: true
  validates :start_time, presence: true

  # The place the story opens in. Story::Generator creates it as a stub
  # alongside the story, so it is the story's oldest location; realizing it is
  # Location::Generator.opening's whole job.
  #
  # Reads the in-memory association before the story is saved: Story::Generator
  # returns an unsaved story with its opening room already attached, and a
  # relation query on an unsaved owner finds nothing.
  def opening_location
    return locations.first unless persisted?

    locations.order(:id).first
  end

  def create_character
    character = Character::Generator.new(self).generate
    if !character.save
      raise "Failed to save character: #{character.errors.full_messages.join(", ")}"
    end

    character
  end
end
