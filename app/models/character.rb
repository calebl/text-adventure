# Somebody in a story, and WHERE THEY ARE is now part of what this class is
# for. Everything else about them -- the sheet, the pronouns, the prompt every
# conversation is built on -- is below; this header is about the one column
# that changed what the game can know.
#
# ------------------------------------------------------------------------
# WHEREABOUTS: ONE PLACE AT A TIME, AND THE APP OWNS IT.
#
# `characters.location_id` is the `Item` shape applied to people, chosen by the
# captain over making the scene cast authoritative. Before it, `Character`
# belonged to a story and to the scenes it appeared in, and that was the whole
# answer to "where is Ammon Brace": whereabouts were whatever the last ARRIVAL
# scene's cast said, and only an arrival writes a cast -- 296 of the 480
# baseline turns of 2026-09-03 have one and the other 184 have none. So the
# room's cast was regenerated from scratch on every arrival and quietly dropped
# the people the world is about. Arriving at The Tide Post recorded the
# protagonist alone, on all three runs checked, in a world whose premise is Neb
# Halloran chained to that post; the narrator put him there and no record kept
# him.
#
# `Character.present_in(location)` IS THE CLOSED SET, the same way
# `Playthrough#items_lying_in(location)` is the one `take` resolves against.
# `Playthrough::Classifier#characters_here` reads it, `Playthrough::Moment#others`
# reads it, `Playthrough::Mechanics`'s `present` line reads it, and the arrival
# cast a `Scene` records is written FROM it rather than the other way round.
# One answer, one query, and nothing infers presence from prose.
#
# WHO IS NOT IN IT, and this is deliberate: the PARTY. The protagonist and
# anyone `is_companion` are wherever the PLAYTHROUGH is, and a playthrough is
# per-player -- two people walking the same seeded world stand in different
# rooms at once. A story-level column cannot hold two answers, so the party's
# position stays `playthroughs.current_location_id` and is derived, while this
# column holds where the WORLD's people are: the ones who stay put until
# something moves them. `Scene::Generator.characters_present` is the one place
# the two are added together.
#
# WHAT MOVES SOMEBODY, and it is a closed list:
#
#   the seed file        `characters[].location` in db/seeds/worlds/*.yml,
#                        loaded by `WorldSeed::Loader`. A seeded character the
#                        file does not place stays nowhere and
#                        `rake game:doctor` reports it -- unless the file says
#                        `absent: true`, which is nowhere ON PURPOSE. See
#                        NOWHERE ON PURPOSE below.
#   placement            `Character::Registry`, the people half of the noun
#                        registry: it places somebody who is nowhere and it
#                        NEVER silently moves somebody who is already
#                        somewhere. That rule is the Tide Post defect written
#                        down.
#   `#move_to!`          the explicit engine call, for a mechanic that means to
#                        move a person. Nothing invokes it yet, and that is the
#                        point: movement is a decision, not a side effect.
#   the backfill         `rake game:backfill_whereabouts`, once, from the old
#                        arrival casts -- and it refuses to guess.
#
# WHAT DOES NOT: prose. No narrator tool, no per-turn model check, no scan of a
# narration for a name. The standing constraint (AGENTS.md) is that the engine
# decides state and the prose is TOLD, and a mechanic that depended on a model
# calling a tool would stop working the day a model stopped complying.
#
# ------------------------------------------------------------------------
# NOWHERE ON PURPOSE: `characters.deliberately_absent`.
#
# Nowhere is a real state and the doctor reports it, because somebody
# `Character.present_in` never offers is somebody the player can never speak
# to. One of the three checked-in worlds means it anyway: `The Unrecorded Hour`
# leaves Perrin Lasco nowhere because its whole premise is that he has been
# removed from the world, and the doctor reported that on every run -- a
# warning about the world working as written, which is how a person learns to
# stop reading warnings.
#
# This boolean is the difference between the two nowheres, and it is a fact
# about the PERSON rather than a lookup: only three stories in the database
# have a checked-in file, so a caller that answered "is this deliberate" by
# reading YAML would have no answer for a generated world.
#
#   the file says it     `characters[].absent: true`, written by
#                        `WorldSeed::Loader` and exported back by
#                        `WorldSeed::Exporter`.
#   `#absent!`           the explicit engine call: nowhere, and meant.
#   `#move_to!(room)`    CLEARS it. Bringing Perrin back is the story's
#                        business, and a person standing in a room is not
#                        absent from the world.
#   `Character::Registry` never places one -- the second half of the rule the
#                        registry exists for.
# ------------------------------------------------------------------------
class Character < ApplicationRecord
  belongs_to :story
  belongs_to :race
  # WHERE THEY ARE. Optional because "nowhere yet" is a real state and the only
  # honest one for somebody the seed did not place, somebody generated before
  # this column existed, or somebody whose room has been deleted. See the
  # header, and `Story::Doctor#whereabouts` for what each of those reads as.
  belongs_to :location, optional: true
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
  validate :location_belongs_to_story
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

  # THE CLOSED SET `talk` RESOLVES AGAINST: the people the records place in this
  # room. The exact counterpart of `Playthrough#items_lying_in`, and read through
  # `Scene::Generator.characters_present` by everything that asks who is here.
  #
  # WHO IS IN A ROOM IS THE WORLD'S and stays story-level, which is where the
  # two part company: since the captain's ruling of 2026-09-04 each playthrough
  # holds its own copy of what is LYING in a room, and the people standing in it
  # are shared exactly as the room itself is.
  #
  # Ordered by id so two people in one room are offered in a stable order --
  # the same reason a game's own floor is ordered where it is read.
  scope :present_in, ->(location) { where(location: location).order(:id) }

  # Nobody has said where they are. Honest, and reported rather than repaired:
  # see the header, and `Story::Doctor`.
  scope :nowhere, -> { where(location_id: nil) }

  scope :somewhere, -> { where.not(location_id: nil) }

  # NOWHERE AND MEANT. See the header: the state a seed file asserts with
  # `absent: true`, told apart from the nowhere that is an accident so that the
  # doctor can report one and stay quiet about the other.
  scope :deliberately_absent, -> { where(deliberately_absent: true) }

  def nowhere? = location_id.nil?

  def somewhere? = location_id.present?

  # Nowhere, on purpose, and still nowhere. Both halves are asked because the
  # marker and the column can contradict each other -- a row written outside
  # the app, or a file that grew a `location` for somebody it also marks absent
  # -- and `Story::Doctor` reports that contradiction rather than picking a
  # winner silently.
  def absent? = deliberately_absent? && nowhere?

  # Where they are, in one sentence, for a report a person reads. The same
  # shape `Item#whereabouts` has and for the same reason -- `rake game:doctor`
  # and the backfill both print it.
  def whereabouts
    return "nowhere on purpose" if absent?
    return "nowhere" if nowhere?

    "in #{location.name}"
  end

  # THE EXPLICIT ENGINE CALL, and the only unconditional one. It moves somebody
  # whether or not they were already somewhere, so it is what a mechanic that
  # MEANS to move a person uses -- an escort, a summons, a companion following
  # the party -- and it is deliberately not called anywhere yet. Placement, the
  # thing that happens on its own, goes through `Character::Registry`, which
  # refuses to move somebody who is already somewhere.
  #
  # `nil` is legal and means "off the map": a person can stop being anywhere.
  #
  # A ROOM CLEARS `deliberately_absent`. An engine mechanic that brings Perrin
  # Lasco back into the world is the story's business, and once he is standing
  # in Ward Office 12 the premise no longer holds -- leaving the marker set
  # would mean a record that says "absent on purpose" about somebody the
  # classifier is offering as a person to talk to. `move_to!(nil)` leaves it
  # exactly as it was, because taking somebody off the map does not decide
  # whether that is the story or an accident; `#absent!` is the call that says
  # it is the story.
  def move_to!(location)
    update!(location: location, deliberately_absent: location ? false : deliberately_absent)
  end

  # NOWHERE, AND MEANT: the explicit counterpart of `#move_to!` for the state a
  # seed file asserts with `absent: true`. `WorldSeed::Loader` writes it on
  # load and `Story::Repair` writes it for a world seeded before the marker
  # existed; nothing else in the app decides that somebody's absence is the
  # premise of a world.
  def absent!
    update!(location: nil, deliberately_absent: true)
  end

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

  # A character stands in a room of their own story. The counterpart of
  # `race_belongs_to_story_universe` and of `Item#in_exactly_one_place`: a
  # whereabouts pointing into another world is a row no closed set can offer,
  # because `Character.present_in` is always asked about one story's rooms.
  def location_belongs_to_story
    return if location.nil? || story_id.nil?
    return if location.story_id == story_id

    errors.add(:location, "must be a place in this story")
  end

  # A character's race is picked from the list generated for their universe, so
  # a race from a different universe would silently contradict the setting.
  def race_belongs_to_story_universe
    return if race.nil? || story.nil?
    return if race.universe_id == story.universe_id

    errors.add(:race, "must belong to the story's universe")
  end
end
