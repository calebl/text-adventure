class Character < ApplicationRecord
  belongs_to :story
  has_many :interactions, dependent: :destroy
  has_many :items, dependent: :destroy
  has_and_belongs_to_many :scenes

  enum :sex, { male: "male", female: "female", non_binary: "non-binary", transgender: "transgender" }
  attribute :is_companion, :boolean, default: false

  validates :fullname, presence: true
  validates :age, presence: true, numericality: { greater_than: 0 }
  validates :sex, presence: true, inclusion: { in: sexes.keys }
  validates :race, presence: true
  validates :backstory, presence: true
  validates :personality, presence: true
  validates :appearance, presence: true
  validates :likes, presence: true
  validates :dislikes, presence: true
  validates :fears, presence: true

  def chat
    BaseAgent.new.with_instructions(interaction_instructions)
  end

  def interaction_instructions
    <<~INTERACTION_INSTRUCTIONS

      This is the universe in which you live
      ## Universe Details
      physics: #{story.universe.physics}
      technology: #{story.universe.technology}
      weapons: #{story.universe.weapons}
      races: #{story.universe.races}
      civilizations: #{story.universe.civilizations}
      geographies: #{story.universe.geographies}
      history: #{story.universe.history}
      economics: #{story.universe.economics}
      politics: #{story.universe.politics}
      religion: #{story.universe.religion}

      You are playing a character in a story. This is your character sheet.
      Pretend you are this character in all of your responses.

      ## Character Sheet
      full name: #{fullname}
      nickname: #{nickname}
      age: #{age}
      sex: #{sex}
      race: #{race}
      backstory: #{backstory}
      personality: #{personality}
      appearance: #{appearance}
      likes: #{likes}
      dislikes: #{dislikes}
      fears: #{fears}

      If someone asks you a question, you should respond as if you are the character. NEVER BREAK CHARACTER.
      When you are speaking, surround your response with quotes. When you are thinking, do not surround your response with quotes.

      Refer to yourself in third person only.

    INTERACTION_INSTRUCTIONS
  end
end
