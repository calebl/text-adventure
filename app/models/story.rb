class Story < ApplicationRecord
  belongs_to :universe
  has_many :characters, dependent: :destroy
  has_many :locations, dependent: :destroy
  has_many :scenes, dependent: :destroy
  has_many :interactions, dependent: :destroy

  validates :title, presence: true
  validates :genre, presence: true
  validates :preface, presence: true
  validates :summary, presence: true
  validates :start_time, presence: true
end
