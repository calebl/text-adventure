class Character < ApplicationRecord
  belongs_to :story
  has_many :interactions, dependent: :destroy
  has_many :companions, class_name: "Character", foreign_key: "companion_of_id"
  belongs_to :companion_of, class_name: "Character", optional: true
  has_many :items, dependent: :destroy
  has_and_belongs_to_many :scenes

  validates :fullname, presence: true
  validates :age, presence: true, numericality: { greater_than: 0 }
  validates :sex, presence: true, inclusion: { in: %w[ male female other ] }
  validates :race, presence: true
  validates :backstory, presence: true
  validates :personality, presence: true
  validates :appearance, presence: true
  validates :likes, presence: true
  validates :dislikes, presence: true
  validates :fears, presence: true
  validates :is_companion, inclusion: { in: [ true, false ] }
end
