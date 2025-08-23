class Universe < ApplicationRecord
  has_many :stories, dependent: :destroy

  validates :physics, presence: true
  validates :technology, presence: true
  validates :weapons, presence: true
  validates :races, presence: true
  validates :civilizations, presence: true
  validates :geographies, presence: true
  validates :history, presence: true
  validates :economics, presence: true
  validates :politics, presence: true
  validates :religion, presence: true
end
