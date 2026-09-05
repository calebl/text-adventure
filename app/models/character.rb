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
#
# ------------------------------------------------------------------------
# THE STAT BLOCK: `level`, `hit_die` AND THREE ABILITIES, AND THE ENGINE ROLLS
# EVERY ONE OF THEM.
#
# The captain's ruling of 2026-09-04: *"A model cannot set an NPC's numbers, the
# engine rolls them."* So there is no field for a stat on any schema, nothing in
# any prompt asks for one, and every number below that the app itself wrote came
# out of `Character::StatBlock` through `Roll`.
#
#   `hit_die`   HOW TOUGH THIS BODY IS. One of `HIT_DICE`, chosen by a roll
#               (`Roll.one_of`) and never by a model. `#max_hp` is derived from
#               it and from the level, and from NOTHING ELSE.
#   `level`     STORED AND INERT. Nothing reads it for behaviour, nothing
#               advances it, and `#advance!` is the explicit call that would --
#               deliberately called from nowhere, exactly as `#move_to!` was
#               when it landed. Advancement wants a source (the queued
#               `ta-story-arc`'s quest completion is the obvious one) and
#               nothing here invents one.
#   `strength`  WHAT A BODY CAN DO, three integers in `ABILITY_RANGE`, each 3d6
#   `dexterity` (`Roll.pool`). The captain's ruling of 2026-09-04, evening:
#   `will`      *"let's go with the 3 abilities"* -- strength, dexterity, will,
#               and exactly those three. It corrects the earlier *"no abilities
#               for now"*, which was a misunderstanding of the word: an ability
#               here is a number a die is thrown against, not a special power.
#
# `#max_hp` GAINS NOTHING FROM AN ABILITY, and this sentence is here so the
# question is not reopened: there is no constitution among the three, `will` is
# NERVE RATHER THAN STAMINA, and the body's capacity is `hit_die` and nothing
# else. An ability term would give one column two jobs and let a re-seed
# silently move every playthrough's ceiling.
#
# THE CHECK IS d20-UNDER THE SCORE and `#check` is the whole of it: one die
# against one column, with a penalty subtracted from the target rather than
# added to the die, so the difficulty is a parameter on the thing being tried
# and never a second table. `Character::Check` is what comes back -- a record,
# printable, and re-derivable because `Roll` is seeded. There is ONE kernel: no
# ability modifier, no DC ladder, no advantage, no skill.
#
# NULLABLE -- all five -- on this class's own rule. A character written before
# the columns existed has no stat block and no abilities, and each is a real
# state `rake game:doctor` reports (`character_without_a_stat_block`,
# `character_without_abilities`) rather than one anything invents a value for --
# the same rule `location_id` above is nullable under.
# `rake game:backfill_stat_blocks` rolls whatever is missing for every such row,
# offline and deterministically, and it is one of `bin/update`'s steps.
#
# TWO PREDICATES AND THEY DO NOT MERGE. `#stat_block?` is `level` and `hit_die`
# -- `#max_hp`'s gate, and through it every `Playthrough::Vitals` row in the
# database -- and `#abilities?` is the three. Folding the abilities into
# `#stat_block?` would make every existing maximum nil and every existing game's
# condition unreadable in the window between the migration and the backfill.
#
# WHAT IS *NOT* HERE, and belongs one layer down: how much is left of the body.
# `characters.hit_die` is who somebody IS, which two people playing one world
# both meet; what has HAPPENED to them is `Playthrough::Vitals`, one row per
# game. The same split `Item` makes between the world's own rows and a
# playthrough's copies, and made for the same reason.
#
# ------------------------------------------------------------------------
# HOSTILE: `characters.hostile`, AND A MONSTER IS AN ORDINARY PERSON WITH IT SET.
#
# The captain's ruling of 2026-09-04: *"a universe should be able to have
# monsters as well as characters."* It is answered here rather than with an STI
# subtype or a `monsters` table, because every seam a fight needs already exists
# on this class and on nothing else -- a body, a whereabouts, hands
# (`items.character_id`), a place in a room's cast, a per-playthrough condition,
# a seed entry, a doctor finding, a name in the closed sets. It is
# `locations.mobile`'s argument said one table over: *"a mobile location is an
# ordinary location in every other respect"*, and what differs about a monster
# is whether it attacks.
#
# NOT NULL, DEFAULT FALSE -- `items.readable`'s shape, and the reason no
# `bin/update` step was needed for it: an existing world has no monsters and the
# default says so. The five columns above are nullable because "nobody has
# rolled one" is a real state; there is no such state here.
#
#   a seed file          `characters[].hostile: true`, assigned straight through
#                        by `WorldSeed::Loader` and written back by
#                        `WorldSeed::Exporter`. The file IS the decision, so it
#                        can also put a tame beast of a monstrous race in a room.
#   DERIVED at creation  `.hostile_by_default?` -- a generated character whose
#                        race is monstrous is hostile. The captain's seventh
#                        ruling of 2026-09-04 evening, one line, read by the
#                        only two things that write a character outside a seed
#                        file (`Character::Registry`, `Character::Generator`).
#   NO MODEL, EVER       no schema has a field for it, no prompt mentions it,
#                        and nothing scans prose for one.
#                        `EngineSweep::Invariants#hostility_unmoved` is the
#                        assertion that no typed line moves it -- the same
#                        statement `stat_blocks_unmoved` makes about a body, and
#                        it covers `races.monstrous` and `locations.danger` too
#                        because those are not columns on a character.
#
# THE NINE FIELDS ARE NOT RELAXED FOR A MONSTER. `race`, `age`, `sex` and the
# six sheet fields are all `presence: true` and stay that way: every one of them
# is interpolated into `#interaction_instructions`, so a monster you can talk to
# -- a hound that growls, a bailiff who threatens before he swings -- comes free,
# and it is a feature of this game rather than an accident. An age and a sex on
# a swarm are the honest oddity and are left as they are. Something genuinely
# impersonal (a flood, a collapsing floor) is not a `Character` at all; it is a
# hazard, and that is a later slice.
#
# WHO IS FIGHTING A PARTY IS *NOT* THIS COLUMN ON ITS OWN. `Playthrough#foes_in`
# is the one reader: the world says who is hostile, a GAME says which of them is
# still standing. Nothing per-playthrough about hostility exists yet -- no
# provoked mark, no engaged-at -- and that is a later slice by ruling.
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
  # HOW MUCH IS LEFT OF THIS BODY, one row per game that has met them. Destroyed
  # with the character on the same reasoning the chats are: a condition with
  # nobody to be the condition OF is a row no reader can ever answer from. See
  # `Playthrough::Vitals`, and read it through `Playthrough#vitals_for` rather
  # than through this association -- one reader, for the same reason
  # `Character.present_in` is the one reader of who is in a room.
  has_many :vitals, class_name: "Playthrough::Vitals", dependent: :destroy,
                    inverse_of: :character

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

  # THE DICE A BODY CAN BE. Three, and they are the shapes an open-RPG stat
  # block has always used: a d6 body is frail, a d8 body ordinary, a d10 body
  # hard to put down. It is a closed list rather than a range because it is what
  # `Roll.one_of` draws from -- the engine picks one of three, and a number
  # outside them arrived from somewhere that is not the engine.
  HIT_DICE = [ 6, 8, 10 ].freeze

  # WHAT A LEVEL MAY BE. Stored and inert (see the header), so this bounds a
  # column nothing advances -- which is exactly when a bound is cheap and worth
  # having: the day something does advance it, the ceiling is already written
  # down.
  LEVELS = (1..20).freeze

  # THE THREE ABILITIES, AND THERE ARE EXACTLY THREE. The captain's ruling of
  # 2026-09-04, evening: *"let's go with the 3 abilities"* -- strength,
  # dexterity, will. A fourth is a ruling nobody has made, so this list is the
  # closed one every reader iterates: the validations below, `#abilities?`,
  # `Character::StatBlock`, `Character::StatBackfill`, `Story::Doctor`,
  # `WorldSeed::Loader`, `WorldSeed::Exporter` and
  # `EngineSweep::Invariants#stat_blocks_unmoved` all read it rather than
  # naming the three columns again.
  #
  # THE ORDER IS LOAD-BEARING and it is this one: `Character::StatBlock` draws
  # them from one generator in this sequence, so a roll is re-derivable for ever
  # -- which is what makes `DRY_RUN=1` worth anything. Reordering this list
  # re-rolls every body the backfill would ever write.
  ABILITIES = %i[strength dexterity will].freeze

  # WHAT AN ABILITY MAY BE: 3d6, so 3..18, and the range IS the roll's own
  # bounds rather than a taste. A number outside it arrived from somewhere that
  # is not the engine -- which is `HIT_DICE`'s argument for being a closed list,
  # one column over.
  ABILITY_RANGE = (3..18).freeze

  # THE d20 EVERY CHECK IS THROWN ON. One die, one column, one comparison; see
  # `#check`.
  CHECK_DIE = 20

  # ONE ATTEMPT AT SOMETHING, AND IT READS OUT AS A RECORD.
  #
  # d20-under the score: the check passes when the die comes up at or below
  # `score - penalty`. The penalty is subtracted from the TARGET rather than
  # added to the die, because that keeps the difficulty a parameter on the thing
  # being tried -- the shape `LocationConnection::DISTANCES` and
  # `world_mechanics.cadence` already have -- instead of a second table of
  # numbers to tune beside the ability itself.
  #
  # AT `target <= 0` NO DIE IS THROWN AT ALL. The pass rate there is zero for
  # ever, so rolling would be theatre: `#impossible?` is true, `#die` is nil,
  # and the honest answer for the engine to give is that the thing cannot be
  # done -- refusal-shaped, and the same shape `Playthrough::Refusal` gives a
  # line the engine will not play. A caller that printed a die here would be
  # printing a number that decided nothing.
  #
  # A value and not a record, like `Playthrough::Vitals::Condition`: every
  # consumer only reads.
  Check = Data.define(:ability, :score, :penalty, :die) do
    def target = score - penalty

    def impossible? = target <= 0

    def rolled? = !die.nil?

    def passed? = rolled? && die <= target

    def failed? = rolled? && !passed?

    # `check strength -> d20(7) <= 12 PASS`, which is what `rake game:mechanics`
    # prints and `rake game:sweep` asserts. One definition, so the read-out and
    # a log line cannot describe the same roll two ways.
    def to_s
      return "#{ability} -> #{score} - #{penalty} = #{target}, IMPOSSIBLE (no roll)" if impossible?

      "#{ability} -> d#{CHECK_DIE}(#{die}) <= #{target} #{passed? ? "PASS" : "FAIL"}"
    end
  end

  # Two people in one story cannot share a full name -- a player has no other
  # handle on who they are talking to. Case-insensitive, and backed by a unique
  # index on (story_id, LOWER(fullname)) so it holds under concurrency too.
  # `nickname` is deliberately NOT constrained: two people plausibly answer to
  # "Doc" in the same story, and the full name is the identity.
  validates :fullname, presence: true,
                       uniqueness: { scope: :story_id, case_sensitive: false }
  validates :age, presence: true, numericality: { greater_than: 0 }
  # THE STAT BLOCK, VALIDATED ONLY WHEN IT IS THERE. Both columns are nullable
  # because "nobody has rolled one" is a real state (see the header), and both
  # are refused a value outside the engine's own tables -- a hit die of 7 or a
  # level of 0 is a number no roll in this app can produce.
  validates :level, inclusion: { in: LEVELS }, allow_nil: true
  validates :hit_die, inclusion: { in: HIT_DICE }, allow_nil: true
  validate :a_stat_block_is_whole
  # THE ABILITIES, VALIDATED THE SAME WAY AND SEPARATELY. Nullable for the same
  # reason and refused a value outside `ABILITY_RANGE` for the same reason: 3d6
  # cannot come up 2 or 19, so a number that did arrived from somewhere that is
  # not the engine. Whole-or-nothing is `#abilities_are_whole`, the mirror of
  # `#a_stat_block_is_whole` -- and a SEPARATE validation, because the two
  # halves are separate facts and the doctor reports them separately.
  ABILITIES.each { |ability| validates ability, inclusion: { in: ABILITY_RANGE }, allow_nil: true }
  validate :abilities_are_whole
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

  # WHO ATTACKS THE PARTY, AND IT IS THE WORLD THAT SAYS SO.
  #
  # `characters.hostile` is on `hit_die`'s side of the layer split: rolled or
  # derived by the engine, written by a seed file, and written by NO MODEL EVER
  # -- there is no field for it on any schema, no prompt mentions it, and
  # `EngineSweep::Invariants#hostility_unmoved` is the assertion that no typed
  # line moves it. It is a flag on the record rather than a subclass or a second
  # table, which is `locations.mobile`'s own argument said one table over: a
  # monster is an ordinary person in every respect but one, and every seam a
  # fight needs -- a body, a whereabouts, hands, a place in a room's cast, a
  # per-playthrough condition, a seed entry, a doctor finding -- already exists
  # here and on nothing else.
  #
  # READ IT THROUGH `Playthrough#foes_in`, not through this scope: the world
  # says who is hostile and a GAME says which of them is still standing, and a
  # caller that asked only this one would offer a corpse a fight.
  scope :hostile, -> { where(hostile: true) }

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

  # HOSTILE BY DEFAULT IF THE RACE IS MONSTROUS -- the captain's seventh ruling
  # of 2026-09-04 evening, and it is ONE DERIVED LINE living in one place with
  # two callers (`Character::Registry` and `Character::Generator`, the only two
  # things in the app that write a character outside a seed file). No model
  # input reaches it: the race is the engine's own choice, drawn from the pool
  # the room's `danger` decides, and this reads a column off it.
  #
  # BY DEFAULT, WHICH MEANS A FILE MAY OVERRIDE IT. `WorldSeed::Loader` assigns
  # `characters[].hostile` straight through, so a hand-authored world can put a
  # tame beast or a monstrous race that keeps to itself into a room. This is the
  # answer for everybody the ENGINE writes, where there is nobody to ask.
  def self.hostile_by_default?(race) = race.present? && race.monstrous?

  # WHETHER THE ENGINE HAS A BODY FOR THIS PERSON AT ALL. Both halves, because
  # `#max_hp` needs both and half a stat block is not one -- `#a_stat_block_is_whole`
  # refuses to save one, so in practice this is one question asked once.
  def stat_block? = level.present? && hit_die.present?

  # WHETHER THE ENGINE HAS THE THREE ABILITIES FOR THIS PERSON. Its own
  # predicate, deliberately NOT folded into `#stat_block?` above: that one gates
  # `#max_hp` and through it every condition row in the database, and widening it
  # would make every existing maximum nil between the migration and the
  # backfill. `#abilities_are_whole` refuses to save a partial set, so in
  # practice this is one question asked once.
  def abilities? = ABILITIES.all? { |ability| self[ability].present? }

  # ONE ATTEMPT AT SOMETHING, d20-UNDER THE ABILITY. `Character::Check` above is
  # the whole rule and its header the whole reasoning; this is the call.
  #
  #   character.check(:strength, penalty: 2, rng: Roll.generator(...))
  #
  # `rng:` IS REQUIRED AND THERE IS NO DEFAULT, on `Roll`'s standing rule: a
  # caller throwing several dice for one decision throws them from one seed in
  # one order, and a defaulted generator here would make a check un-re-derivable
  # -- which is exactly the property `rake game:sweep` asserts against.
  #
  # `nil` for somebody with no abilities, which is what makes it safe to ask of
  # anybody: it is the same honest nothing `#max_hp` answers for a body with no
  # stat block, and the caller decides what to say about it.
  #
  # NO DIE IS THROWN when the target is zero or less: the score is read, the
  # `Check` says `impossible?`, and the generator is left untouched -- so a
  # caller that asks the impossible does not silently consume somebody else's
  # roll.
  def check(ability, penalty: 0, rng:)
    ability = ability.to_sym
    raise ArgumentError, "#{ability.inspect} is not one of #{ABILITIES.join(", ")}" unless ABILITIES.include?(ability)
    return nil unless abilities?

    score = self[ability]
    target = score - penalty.to_i
    die = target.positive? ? Roll.die(CHECK_DIE, rng: rng) : nil

    Check.new(ability: ability, score: score, penalty: penalty.to_i, die: die)
  end

  # HOW MUCH THIS BODY CAN HOLD, DERIVED AND NEVER STORED.
  #
  #   max_hp = hit_die + (level - 1) * (hit_die / 2 + 1)
  #
  # A first level is the whole die -- the toughest a body of that kind starts --
  # and every level after it adds the die's AVERAGE ROUNDED UP, which is
  # `hit_die / 2 + 1` in integer arithmetic (a d8 adds 5). It is the arithmetic
  # an open-RPG stat block has always used with the ability term struck out.
  #
  # THE TERM STAYS STRUCK OUT NOW THAT THERE ARE ABILITIES, and that is a
  # decision rather than an oversight: none of the three is a constitution,
  # `will` is nerve rather than stamina, and the body's capacity is `hit_die`.
  # An ability term would give one column two jobs and let a re-seed editing
  # `will` silently move every playthrough's ceiling.
  #
  # DERIVED SO THERE IS ONE NUMBER PER BODY AND NOT TWO. A stored maximum is a
  # second place the same fact lives, and the day a re-seed lowers a hit die the
  # two would disagree with nothing to say which was right.
  #
  # Nil for somebody with no stat block, which is what makes it safe to ask of
  # anybody: `Playthrough::Vitals` reads nil as "there is no maximum to start
  # them at" and writes no row.
  def max_hp
    return nil unless stat_block?

    hit_die + (level - 1) * (hit_die / 2 + 1)
  end

  # THE EXPLICIT ENGINE CALL FOR A LEVEL, and it is deliberately called from
  # nowhere -- exactly as `#move_to!` was when it landed, and for the same
  # reason. Levels are STORED AND INERT in this PR (the captain's ruling of
  # 2026-09-04): advancement needs a source, this game has no kills, and
  # inventing one here would be inventing a rule nobody asked for. When there is
  # a source -- a quest step completed is the obvious one -- this is the
  # statement it calls, and `#max_hp` follows from it with nothing else to
  # change.
  def advance!(to = level.to_i + 1)
    update!(level: to)
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

  # HALF A STAT BLOCK IS NOT ONE. `#max_hp` needs both columns, so a row with a
  # hit die and no level is somebody the engine cannot say anything about while
  # looking as though it can -- worse than the honest nothing, which is what
  # `rake game:doctor` reports and `rake game:backfill_stat_blocks` fills in.
  def a_stat_block_is_whole
    return if level.present? == hit_die.present?

    errors.add(:base, "has half a stat block (#{level.present? ? "a level and no hit die" : "a hit die and no level"}); " \
                      "the engine rolls both together or neither")
  end

  # A PARTIAL SET OF ABILITIES IS NOT A SET. The mirror of
  # `#a_stat_block_is_whole` and separate from it on purpose: `Character::StatBlock`
  # rolls the three together or not at all, so a row with a strength and no will
  # is somebody `#check(:will)` cannot answer about while `#check(:strength)`
  # looks as though the sheet were complete. `rake game:doctor` reports the
  # honest nothing (`character_without_abilities`) and
  # `rake game:backfill_stat_blocks` fills it in.
  def abilities_are_whole
    present = ABILITIES.count { |ability| self[ability].present? }
    return if present.zero? || present == ABILITIES.size

    missing = ABILITIES.reject { |ability| self[ability].present? }
    errors.add(:base, "has #{present} of #{ABILITIES.size} abilities (no #{missing.join(", no ")}); " \
                      "the engine rolls all three together or none")
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
