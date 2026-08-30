class Story < ApplicationRecord
  belongs_to :universe
  has_many :characters, dependent: :destroy
  has_many :locations, dependent: :destroy
  has_many :scenes, dependent: :destroy
  # Interactions hang off characters; destroying the story destroys the
  # characters, which take their own interactions with them.
  has_many :interactions, through: :characters

  validates :title, presence: true
  validates :genre, presence: true
  validates :preface, presence: true
  validates :summary, presence: true
  validates :start_time, presence: true

  def create_character
    character = Character::Generator.new(self).generate
    if !character.save
      raise "Failed to save character: #{character.errors.full_messages.join(", ")}"
    end

    character
  end
end
