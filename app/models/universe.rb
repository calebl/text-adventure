class Universe < ApplicationRecord
  has_many :stories, dependent: :destroy
  has_many :races, dependent: :destroy

  validates :physics, presence: true
  validates :technology, presence: true
  validates :weapons, presence: true
  validates :civilizations, presence: true
  validates :geographies, presence: true
  validates :history, presence: true
  validates :economics, presence: true
  validates :politics, presence: true
  validates :religion, presence: true
  validates :races, presence: true

  # One "Name -- description" line per race. Characters are assigned from this
  # list, so prompts need to show what is on offer.
  def races_summary
    races.map { |race| "#{race.name} -- #{race.description}" }.join("\n")
  end

  # The universe as prompt context. Every generator needs this same block, and
  # a field added here should reach all of them at once.
  def prompt_details
    <<~DETAILS
      physics: #{physics}
      technology: #{technology}
      weapons: #{weapons}
      geographies: #{geographies}
      races:
      #{races_summary}
      civilizations: #{civilizations}
      history: #{history}
      economics: #{economics}
      politics: #{politics}
      religion: #{religion}
    DETAILS
  end
end
