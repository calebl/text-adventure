class Character < ApplicationRecord
  belongs_to :story
  belongs_to :race
  has_many :interactions, dependent: :destroy
  has_many :items, dependent: :destroy
  has_and_belongs_to_many :scenes
  has_many :playthroughs, dependent: :nullify
  # The durable conversations somebody is having with this character, one per
  # playthrough. See Chat::CHARACTER.
  has_many :chats, dependent: :destroy

  enum :sex, { male: "male", female: "female", non_binary: "non-binary",
               trans_woman: "trans woman", trans_man: "trans man" }

  # The pronouns to use for a character. A trans woman is a woman and a trans man
  # is a man, so they map to exactly what any other woman or man maps to -- the
  # entries are not a special case bolted on beside the others, they are the same
  # answer.
  #
  # Keyed on the enum KEY, which is what `sex` reads back, so a prompt cannot
  # drift from the rule the way it did when it interpolated `sex` and matched on
  # the stored value. Every key the enum can hold has an entry, and CharacterTest
  # pins that, so the generator cannot roll a sex with no pronouns.
  PRONOUNS = {
    "male" => "he/him/his",
    "female" => "she/her/hers",
    "non_binary" => "they/them/theirs",
    "trans_woman" => "she/her/hers",
    "trans_man" => "he/him/his"
  }.freeze

  # THE SAME PRONOUNS, ONE FORM AT A TIME, for a prompt that has to build a
  # sentence rather than state a rule. "he/him/his" is the right thing to TELL
  # a model; "#{determiner} eyes wide" is what a prompt writing an example
  # sentence needs, and "his/hers/theirs" is the wrong word there. `plural` is
  # for verb agreement: "they turn", "she turns". Keyed on the `PRONOUNS` value
  # so a new entry in that table has to have a row here too.
  Pronouns = Data.define(:subject, :object, :determiner, :possessive, :plural) do
    # The verb form that agrees with the subject pronoun: `verb("turns", "turn")`.
    def agree(singular, plural_form) = plural ? plural_form : singular
  end

  PRONOUN_FORMS = {
    "he/him/his" => Pronouns.new(subject: "he", object: "him", determiner: "his", possessive: "his", plural: false),
    "she/her/hers" => Pronouns.new(subject: "she", object: "her", determiner: "her", possessive: "hers", plural: false),
    "they/them/theirs" => Pronouns.new(subject: "they", object: "them", determiner: "their", possessive: "theirs", plural: true)
  }.freeze

  attribute :is_companion, :boolean, default: false

  # Two people in one story cannot share a full name -- a player has no other
  # handle on who they are talking to. Case-insensitive, and backed by a unique
  # index on (story_id, LOWER(fullname)) so it holds under concurrency too.
  # `nickname` is deliberately NOT constrained: two people plausibly answer to
  # "Doc" in the same story, and the full name is the identity.
  validates :fullname, presence: true,
                       uniqueness: { scope: :story_id, case_sensitive: false }
  validates :age, presence: true, numericality: { greater_than: 0 }
  validates :sex, presence: true, inclusion: { in: sexes.keys }
  validate :race_belongs_to_story_universe
  validate :single_protagonist_per_story
  validates :backstory, presence: true
  validates :personality, presence: true
  validates :appearance, presence: true
  validates :likes, presence: true
  validates :dislikes, presence: true
  validates :fears, presence: true

  # The stored value rather than the enum key -- "trans woman", not
  # "trans_woman" -- so anything that interpolates it reads as English.
  def sex_label
    self.class.sexes[sex]
  end

  # "he/him/his", "she/her/hers", "they/them/theirs". Raises rather than
  # defaulting -- see InteractionAgent#pronoun_rule for why.
  def pronouns
    PRONOUNS.fetch(sex)
  end

  # The forms of those pronouns, for a prompt building a sentence. Raises on a
  # pronoun set the table has no forms for, for the same reason `#pronouns`
  # does: a silent default is how a wrong pronoun goes unnoticed.
  def pronoun_forms
    PRONOUN_FORMS.fetch(pronouns)
  end

  def chat
    BaseAgent.new.with_instructions(interaction_instructions)
  end

  # THE PROMPT EVERY CONVERSATIONAL TURN IS BUILT ON. `InteractionAgent` sends
  # it as the character pass's instructions, and that pass answers under
  # `Interaction::Schema` -- so the registers named in *Voice* below are the
  # registers of those six fields, not of free prose. `action` is the field
  # that holds speech; the thought and feeling fields are the interior ones.
  def interaction_instructions
    <<~INTERACTION_INSTRUCTIONS

      This is the universe in which you live
      ## Universe Details
      #{story.universe.prompt_details(:dialogue)}

      You are playing a character in a story. This is your character sheet.
      Pretend you are this character in all of your responses.

      ## Character Sheet
      full name: #{fullname}
      nickname: #{nickname}
      age: #{age}
      sex: #{sex_label}
      race: #{race.name} -- #{race.description}
      backstory: #{backstory}
      personality: #{personality}
      appearance: #{appearance}
      likes: #{likes}
      dislikes: #{dislikes}
      fears: #{fears}
      #{addressee_section}
      If someone asks you a question, you should respond as if you are the character. NEVER BREAK CHARACTER.

      ## Voice
      You answer in six fields, and each one has its own register.

      pre_thought and post_thought are your private thoughts. Think them in the first person, as "I". Nobody hears them, so nothing in them is a line of speech.
      pre_feeling and post_feeling are two or three words each. No sentences.
      inner_resolution is what you have decided to do, in the first person.
      action is the one field anybody can see: what you visibly do and what you say out loud. Speech goes inside quotes, and only speech does.
      Inside the quotes you are talking out loud: say "I", never your own name. Nobody says "#{fullname} does not know" out loud.
      Outside the quotes you are described from outside: #{nickname.presence || fullname}, #{pronoun_forms.subject}, #{pronoun_forms.determiner}. A bare "I" out there reads as the person you are talking to rather than as you.

      Answer AS #{fullname}, not about #{pronoun_forms.object}. Do not plan the answer and do not weigh what #{nickname.presence || fullname} would probably think -- think the thought and say the line.

    INTERACTION_INSTRUCTIONS
  end

  scope :protagonists, -> { where(is_protagonist: true) }
  scope :companions, -> { where(is_companion: true) }

  private

  # WHO THE CHARACTER IS TALKING TO. `interaction_instructions` used to name
  # nobody at all, so a model asked for a reaction reached for the only handle
  # the prompt left it and called the player "the user" -- 8 of 30 character
  # passes on `mistralai/mistral-medium-3.1`, 8 of 9 on `minimax/minimax-m3`.
  # An NPC with nobody in front of it invents somebody.
  #
  # IT CARRIES WHAT A PERSON IN THE ROOM COULD PERCEIVE, AND NOT THE
  # PROTAGONIST'S SHEET. `backstory`, `personality`, `likes`, `dislikes` and
  # `fears` are the player's interior; handing them to a stranger is a worse
  # bug than the one this fixes, because every NPC in the world would then know
  # what frightens the player before the player had said a word. Name, apparent
  # age, race and appearance are what meeting somebody tells you -- and the
  # name is already public in this app, because `Scene::Generator` puts the
  # protagonist into the arrival cast list by full name and nickname.
  #
  # Pronouns are STATED and the gender label is not, which is
  # `InteractionAgent#pronoun_rule`'s rule and its reasoning: the prompt needs
  # the pronouns, and naming a gender beside them only gives a model something
  # to make an issue of.
  #
  # What this character actually knows about them beyond what they can see
  # arrives the way it should -- `Chat.conversation_with` replays the
  # conversation the two have already had. See `InteractionAgent#character_agent`.
  #
  # Blank when the story has no protagonist (a world can be seeded without one,
  # see `Playthrough::Turn`) and when this character IS the protagonist.
  def addressee_section
    them = story&.protagonist
    return "" if them.nil? || them == self

    <<~ADDRESSEE

      ## Who you are talking to
      The person speaking to you is #{them.fullname}#{" (#{them.nickname})" if them.nickname.present?}.
      Refer to #{them.fullname} as #{them.pronouns}. Use those pronouns and no others.
      apparent age: about #{them.age}
      race: #{them.race&.name}
      what you can see of them: #{them.appearance}

      That is what meeting #{them.fullname} tells you, and it is the whole of
      what you know by sight. You do not know what #{them.fullname} wants, is
      afraid of, or has done, and you do not invent any of it. Anything more
      you learn from what #{them.fullname} says and does, here, now.
    ADDRESSEE
  end

  # The player is exactly one person, so a story cannot have two characters
  # claiming to be them.
  def single_protagonist_per_story
    return unless is_protagonist?
    return if story_id.nil?

    conflict = Character.where(story_id: story_id, is_protagonist: true)
    conflict = conflict.where.not(id: id) if persisted?
    return unless conflict.exists?

    errors.add(:is_protagonist, "is already set on another character in this story")
  end

  # A character's race is picked from the list generated for their universe, so
  # a race from a different universe would silently contradict the setting.
  def race_belongs_to_story_universe
    return if race.nil? || story.nil?
    return if race.universe_id == story.universe_id

    errors.add(:race, "must belong to the story's universe")
  end
end
