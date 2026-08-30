class Character < ApplicationRecord
  belongs_to :story
  belongs_to :race
  has_many :interactions, dependent: :destroy
  has_many :items, dependent: :destroy
  has_and_belongs_to_many :scenes

  enum :sex, { male: "male", female: "female", non_binary: "non-binary", transgender: "transgender" }
  attribute :is_companion, :boolean, default: false

  validates :fullname, presence: true
  validates :age, presence: true, numericality: { greater_than: 0 }
  validates :sex, presence: true, inclusion: { in: sexes.keys }
  validate :race_belongs_to_story_universe
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
      #{story.universe.prompt_details}

      You are playing a character in a story. This is your character sheet.
      Pretend you are this character in all of your responses.

      ## Character Sheet
      full name: #{fullname}
      nickname: #{nickname}
      age: #{age}
      sex: #{sex}
      race: #{race.name} -- #{race.description}
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

  private

  # A character's race is picked from the list generated for their universe, so
  # a race from a different universe would silently contradict the setting.
  def race_belongs_to_story_universe
    return if race.nil? || story.nil?
    return if race.universe_id == story.universe_id

    errors.add(:race, "must belong to the story's universe")
  end
end
