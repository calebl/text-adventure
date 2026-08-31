class Universe < ApplicationRecord
  # Which fields of the universe each kind of prompt is given.
  #
  # This block is re-sent on every downstream call for the life of the world:
  # once when the story is written, once for every room ever built, once for
  # every character generated, and once on EVERY turn of every conversation.
  # At 1,584 tokens for the whole record that was 58% of every input token the
  # app sent. So who is asking matters, and each audience gets the fields it
  # can actually use.
  #
  #   :full      everything. Story generation, which is setting up the world
  #              and has to be consistent with all of it.
  #   :character generating a person: everything except the race list, because
  #              Character::Generator states the one race it picked, with its
  #              full description, immediately below in the same prompt.
  #   :place     building a room: what the world is made of and who lives in
  #              it, not how it is governed or what it believes.
  #   :dialogue  being a person in it: who the peoples are, who holds power and
  #              what they believe -- plus physics, so a character never offers
  #              to do something the world does not allow. Race NAMES, not the
  #              summary: `Character#interaction_instructions` states the
  #              speaker's own race with its full description in the character
  #              sheet immediately below this block, which is the same reason
  #              `:character` drops the list, and a person in conversation needs
  #              to know which peoples exist rather than three sentences on each
  #              one's temperament. The list was 346 of this audience's 930
  #              tokens, re-sent on every turn of every conversation.
  #   :scene     narrating arrival somewhere already written. `:place` minus
  #              everything the location record localises: the room's own
  #              description and lore were generated FROM `:place` context and
  #              already say what this corner of the world looks like and who
  #              lives in it, and both go into the arrival prompt. What they do
  #              not carry is what the world permits, so physics and technology
  #              stay -- narration that has the player strike a match in a world
  #              without fire is the failure this exists to prevent.
  #
  # `:place` and `:dialogue` overlap on physics, race names and civilizations. If they
  # ever converge, this is one trimmed block with two callers rather than
  # audience-specific context, and it should be collapsed and said out loud.
  # `:scene` is a strict subset of `:place` on purpose; if it ever needs a field
  # `:place` does not have, that is a sign the split is wrong.
  AUDIENCE_FIELDS = {
    full: %i[physics technology weapons geographies races civilizations history economics politics religion],
    character: %i[physics technology weapons geographies civilizations history economics politics religion],
    place: %i[physics technology geographies race_names civilizations],
    dialogue: %i[physics race_names civilizations politics religion],
    scene: %i[physics technology]
  }.freeze

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

  # Just the names. A room needs to know who lives in this world; it does not
  # need three sentences on each people's temperament to describe a doorway.
  def race_names
    races.map(&:name).join(", ")
  end

  # The universe as prompt context, for the audience asking. A field added to
  # AUDIENCE_FIELDS reaches every prompt that audience covers at once.
  def prompt_details(audience = :full)
    fields = AUDIENCE_FIELDS.fetch(audience) do
      raise ArgumentError, "unknown prompt audience #{audience.inspect}"
    end

    fields.map { |field| prompt_line(field) }.join("\n") + "\n"
  end

  private

  def prompt_line(field)
    case field
    when :races then "races:\n#{races_summary}"
    when :race_names then "races: #{race_names}"
    else "#{field}: #{public_send(field)}"
    end
  end
end
