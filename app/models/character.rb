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
end
