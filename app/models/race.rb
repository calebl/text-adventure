class Race < ApplicationRecord
  belongs_to :universe
  has_many :characters, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :universe_id, case_sensitive: false }
  validates :description, presence: true
end
