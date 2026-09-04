# A thing in the world, and WHERE IT IS is the whole of what this class is for.
#
# TWO LAYERS, ONE TABLE, and `playthrough_id` is which layer a row is in. The
# captain's ruling of 2026-09-04: *"each play through should have its own copy
# of items. If a location is generated with items in it, that should become the
# initial snapshot that any playthrough uses but what happens to the items after
# that should be managed by the playthrough."*
#
#   THE WORLD LAYER -- a TEMPLATE, `playthrough_id` nil. What a room or a person
#   was seeded or generated with. Written by `WorldSeed::Loader` and
#   `Item::Registry`, exported by `WorldSeed::Exporter`, counted by the caps
#   (`Item::Registry::MAX_PER_ROOM` / `MAX_PER_STORY`, `Story::Doctor`), and
#   NEVER touched by anybody playing. A template is lying in a room or in one of
#   the world's people's hands, and those are its only two places: nobody is
#   playing the world, so the world has no party for anything to be carried by.
#
#   THE PLAYTHROUGH LAYER -- an INSTANCE, `playthrough_id` set. That game's own
#   copy of a template, made at first contact by `Item::Snapshot`. Its place is
#   `location_id` (lying in a room, in that game), `character_id` (in that
#   person's hands, in that game) or NEITHER, which is the party's own hands.
#   THIS IS THE ONLY LAYER PLAY EVER READS OR WRITES: `Playthrough::Classifier`'s
#   closed sets, `Playthrough::Turn#carry!` / `#put_down!` / `#read_item`,
#   `Playthrough::Moment`, `Playthrough::Refusal`'s lists and the
#   `rake game:mechanics` read-out see instances and nothing else.
#
# `template_id` IS THE LINK, and it is what makes the split answerable. It says
# which world row a copy is a copy OF -- so `rake game:doctor` can tell this
# playthrough's ward stamp from a fresh thing of the same name, `Item::Snapshot`
# copies a template exactly once per playthrough however many turns walk back
# through the room, and a template written into a room nobody has visited yet
# still reaches every game that walks in later. It is nullable and NOT validated
# on an instance, deliberately: a template can be deleted out from under its
# copies, and that is a state `rake game:doctor` reports
# (`instance_without_a_template`) rather than one a copy is refused for having.
#
# WHAT THE SHAPE COSTS, stated rather than discovered. Under the old rule an
# item was in exactly one of three places, never two and never NONE, and "none"
# was a real defect -- a row no closed set could ever offer. For an INSTANCE
# "none" is now a place: the party's hands. So the "never none" leg survives on
# templates only, and a bug that nulled an instance's `location_id` would make
# it look carried rather than look broken. Two shapes were considered and
# rejected for costing more than that:
#
#   a fourth column   keep `playthrough_id` meaning the party's hands and add a
#                     separate scope column. The three-place rule survives
#                     verbatim -- and every row that is carried then names its
#                     playthrough twice, in two columns that can disagree, and
#                     every query has to know which one it wants.
#   a second table    `item_instances`. Same problem one table over: the scope
#                     column is the table, so the party still needs a place of
#                     its own, and `Item.in_story`, the caps, the doctor, the
#                     exporter and the audit all fork into two queries that can
#                     drift. One table keeps one `in_story`.
#
# THE PARTY IS NOT THE PROTAGONIST'S HANDS, which is the other shape that would
# have kept "never none": an instance held by `story.protagonist` reads as the
# party, since the party IS the protagonist plus companions. It was rejected
# because `Playthrough#character` is optional and a world can be seeded with no
# protagonist at all, so it would leave some parties with nowhere to put
# anything -- and because it re-couples the inventory to the character row that
# PR 111 spent a migration decoupling it from.
#
# HOW ITEMS COME TO EXIST is `Item::Registry`, and it is still the only thing in
# the app that creates a TEMPLATE: a room's furniture is written as structured
# records the moment the room is realized, out of the same call that describes
# it, exactly the way its exits are. Not by reading narration and not through a
# tool the narrator may or may not call. `Item::Snapshot` is the only thing that
# creates an INSTANCE, and it creates nothing that is not a copy of a template.
#
# AND WHAT IS WRITTEN ON IT, for the things that have writing on them. A note, a
# letter, a sign, a label: `readable` says the thing has words on it and
# `inscription` holds them, so what a note says is a record the engine owns
# rather than a sentence the narrator improvised and nothing kept. It is
# orthogonal to WHERE the thing is and to WHICH LAYER it is in -- a template in a
# room, an instance in an NPC's hands and one a party is carrying all keep their
# text, because writing belongs to the note and not to the shelf. The words
# reach the prose through `Playthrough::Turn#read_fact`, verbatim and stated;
# `Item::Inscriber` writes them once for a readable thing that arrived without
# any, onto the instance AND back onto its template, so the second player's copy
# of the note is born with the same words instead of paying for different ones.
class Item < ApplicationRecord
  # HOW MANY CHARACTERS A THING CAN HAVE WRITTEN ON IT. What a player reads off
  # an object in one turn -- a note, a docket line, a sign, a page of an index --
  # and not a chapter. It is the cap `Item::InscriptionSchema` and
  # `Location::DetailSchema` both ask for and the ceiling this validates, so a
  # generated inscription arriving AT it is a truncated answer
  # (`SanitizesGeneratedText`) rather than a row that quietly will not save.
  INSCRIPTION_LIMIT = 400

  belongs_to :character, optional: true
  belongs_to :location, optional: true
  # WHICH LAYER, and on an instance also WHOSE GAME. Never "who is carrying it"
  # on its own any more -- an instance lying in a room carries this column too.
  # `#carried?` is the question that used to be, and it reads all three columns.
  belongs_to :playthrough, optional: true
  # WHICH WORLD ROW THIS IS A COPY OF. Nil on a template, and nil on an instance
  # whose template has been destroyed -- `dependent: :nullify` rather than
  # `:destroy`, because deleting a world row must not reach into a game in
  # progress and take the thing out of somebody's hands mid-turn. The doctor
  # reports the orphan.
  belongs_to :template, class_name: "Item", optional: true
  has_many :copies, class_name: "Item", foreign_key: :template_id, inverse_of: :template,
                    dependent: :nullify

  validates :name, presence: true
  validates :description, presence: true
  validates :inscription, length: { maximum: INSCRIPTION_LIMIT }
  validate :in_exactly_one_place
  validate :a_template_is_a_template
  validate :inscription_requires_readable

  # THE WORLD'S OWN ROWS and ONE GAME'S OWN ROWS. Every query in the app that
  # means the world says `templates`; every query that means play says
  # `of_playthrough`. A query that says neither is asking about the table, which
  # only `Item.in_story` and `rake game:doctor` legitimately do.
  scope :templates, -> { where(playthrough_id: nil) }
  scope :instances, -> { where.not(playthrough_id: nil) }
  scope :of_playthrough, ->(playthrough) { where(playthrough: playthrough) }

  # WHAT ONE OF THE WORLD'S OWN PEOPLE IS HOLDING. Asked of the protagonist's
  # TEMPLATES it answers the story's starting inventory; asked of anybody else,
  # that person's possessions. Layer-agnostic on purpose, because both layers
  # use it: `Story#starting_inventory` narrows it to templates and
  # `Playthrough#items_held_by` to one game.
  scope :for_character, ->(character) { where(character: character) }
  scope :by_name, ->(name) { where(name: name) }

  # LYING IN A ROOM: no hands on it. Layer-agnostic for the same reason --
  # `Item::Registry` reads the template floor to decide whether a room has room
  # for another thing, and `Playthrough#items_lying_in` reads one game's floor,
  # which is the closed set `take` resolves against.
  #
  # Items in somebody's hands are excluded on purpose -- taking something off a
  # person is a different act with somebody on the other side of it, and there
  # is no record of how they feel about it.
  scope :lying_in, ->(location) { where(location: location, character_id: nil) }

  # Held by one of the world's own people, anywhere in any story.
  scope :held, -> { where.not(character_id: nil) }

  # IN A PARTY'S HANDS: an instance with no room and no holder. `Item::PLACES`
  # empty is what the party's hands ARE, so this is the query that says so once.
  # Read through `Playthrough#carried` rather than here -- one reader, for the
  # same reason `Character.present_in` has one.
  scope :in_hand, -> { where(character_id: nil, location_id: nil) }

  # Carried by any of these parties, which is the union `Story::Audit` and
  # `Eval::Richness` want when they have a story and no playthrough to narrow to.
  scope :carried_by, ->(playthroughs) { where(playthrough: playthroughs).in_hand }

  # EVERY ROW IN ONE STORY, both layers, on whichever side of the place rule it
  # sits. There is no `items.story_id` -- an item is reached through whoever has
  # it -- so this is the three queries that answer for a story, and it is the one
  # place they are written: `Item::Registry`, `Character::Registry`,
  # `Story::Doctor`, `Story::Deletion`, `EngineSweep::Invariants` and
  # `WorldSeed::Loader` all read it here, because a leg missing from one copy is
  # an item the caps cannot see. Narrow it with `.templates` to mean the world.
  scope :in_story, ->(story) {
    where(character_id: story.characters.select(:id))
      .or(where(location_id: story.locations.select(:id)))
      .or(where(playthrough_id: story.playthroughs.select(:id)))
  }

  # THE THINGS WITH WORDS ON THEM. It cuts across both layers and every place: a
  # note lying in a room, a note in an NPC's hands and a note a party is carrying
  # all keep their text, because what is written on a thing is a fact about the
  # thing and not about where it is or whose game it is in. Nothing in the app
  # generates text for an item outside this scope -- see `Item::Inscriber`.
  #
  # A row-level question everywhere it matters -- `#readable?` on the record the
  # classifier resolved -- so this is the set query, for a report about a whole
  # world. `#unwritten` is the one worth asking: a readable thing nobody has read
  # is not a defect (the first read writes it), so no instrument reports it, and
  # what a person actually wants to know is which notes hold words yet.
  scope :readable, -> { where(readable: true) }
  scope :unwritten, -> { readable.where(inscription: nil) }

  # WHICH LAYER THIS ROW IS IN, and it is one question with one column behind it.
  # Read through `#occupies?` rather than off the column for the reason that
  # method documents: a row built through its owner's association carries the
  # owner in memory before it carries the id.
  def template? = !instance?

  def instance? = occupies?(:playthrough_id)

  def held? = occupies?(:character_id)

  def lying? = !held? && occupies?(:location_id)

  # THE PARTY OF ONE PLAYTHROUGH HAS IT IN ITS HANDS. All three columns, because
  # the party is the ABSENCE of a room and a holder inside a game -- which is
  # exactly why a template can never be carried and this returns false for one.
  def carried? = instance? && !held? && !occupies?(:location_id)

  # There is something written on this AND the records hold it. The two halves
  # are separate on purpose: `readable?` is what the world says about the thing,
  # `inscribed?` is whether anybody has written the words down yet, and only the
  # second is what `Playthrough::Turn#read_fact` can quote.
  def inscribed? = readable? && inscription.present?

  # Where it is, in one sentence, for a report a person reads. THE LAYER IS PART
  # OF THE ANSWER: "lying in Ward Office 12" is two different facts depending on
  # whether it is the world's row or one game's copy of it, and a doctor finding
  # that did not say which would send somebody looking in the wrong place.
  def whereabouts
    "#{place_in_words} (#{layer_in_words})"
  end

  def properties_hash
    return {} if properties.blank?
    JSON.parse(properties)
  end

  def properties_hash=(props)
    self.properties = props.to_json
  end

  def add_property(key, value)
    current_properties = properties_hash
    current_properties[key] = value
    self.properties_hash = current_properties
  end

  def get_property(key)
    properties_hash[key]
  end

  def has_property?(key)
    properties_hash.key?(key)
  end

  # THE TWO COLUMNS THAT SAY WHERE A ROW IS, which is a different question from
  # which layer it is in. Public because `Story::Doctor` and
  # `EngineSweep::Invariants` count the same two columns on rows raw SQL or an
  # older schema could have left astray, and because `Item::Snapshot` reads it
  # to know what a copy must NOT bring along.
  PLACES = %i[character_id location_id].freeze

  # WHAT A COPY DOES NOT INHERIT, and everything else it does.
  #
  # A copy of a thing IS that thing: a daybook with no page count, or a note with
  # nothing written on it, is a different object from the one the world
  # describes. So `Item::Snapshot` copies attributes rather than naming fields,
  # and this is the whole of the exception list -- which means the next column
  # added to `items` comes along without anybody remembering to add it. Naming
  # the fields is what left `readable` and `inscription` behind when they landed,
  # so every player's copy of a seeded note opened blank while the world's own
  # row held the words.
  #
  # WHERE it is and WHOSE it is are what must not come along, because they are
  # precisely what the copy exists to differ in; `id` and the timestamps belong
  # to the row rather than to the thing.
  NOT_COPIED = (PLACES.map(&:to_s) + %w[id playthrough_id template_id created_at updated_at]).freeze

  private

  def place_in_words
    return "held by #{character.fullname}" if held?
    return "lying in #{location.name}" if lying?
    return "in the party's hands" if carried?

    "nowhere"
  end

  def layer_in_words
    return "the world's own" if template?

    "playthrough ##{playthrough_id}'s#{" copy of ##{template_id}" if template_id}"
  end

  # WORDS ON A THING THAT HAS NO WRITING ON IT is the state this refuses, and it
  # is refused rather than tidied away because the two columns are one fact read
  # from two sides. `readable` is what closes the set `Item::Inscriber` may ever
  # write into: an inscription on an item nobody marked readable is text that
  # arrived from somewhere other than that gate, which is the shape this whole
  # mechanic exists to make impossible.
  #
  # The other way round is legal and stays legal: a readable thing with no
  # inscription is one nobody has read yet. See `#inscribed?`.
  #
  # It says NOTHING ABOUT WHERE THE THING IS OR WHOSE GAME IT IS IN,
  # deliberately: what is written on a note is a fact about the note, so every
  # place and both layers keep it, and the copy `Item::Snapshot` makes copies the
  # words with everything else.
  def inscription_requires_readable
    return if inscription.blank? || readable?

    errors.add(:inscription, "cannot be written on something that is not readable")
  end

  # EXACTLY ONE PLACE FOR A TEMPLATE, AT MOST ONE FOR AN INSTANCE, and the
  # difference between those two sentences is the whole of the layer split.
  #
  # Two at once is the state that would make `take` unanswerable, in either
  # layer: an item a party is carrying that is also on the floor is takeable and
  # already taken.
  #
  # NONE AT ALL is where the layers part. On a template it is an item nowhere,
  # which no closed set can ever offer and which nothing in the app can reach --
  # the world is not being played, so there is no pair of hands for it to be in.
  # On an instance it is the party's own hands, which is a place, and the most
  # ordinary one there is. See this class's header for what that costs.
  #
  # The message names the columns rather than the fiction because the reader is
  # whoever wrote the row -- a seed file, a registry, a backfill.
  def in_exactly_one_place
    occupied = PLACES.select { |place| occupies?(place) }
    return if occupied.one?
    return if occupied.empty? && instance?

    if occupied.empty?
      errors.add(:base, "is a template in no place at all; the world's own rows lie in a location or " \
                        "are held by a character, and only one playthrough's own copy may be in the party's hands")
    else
      errors.add(:base, "is in #{occupied.size} places at once (#{occupied.join(", ")}); it may only be in one")
    end
  end

  # A TEMPLATE OF A TEMPLATE IS NOT A THING, and neither is a copy of a copy.
  # The link points one way, from the playthrough layer into the world layer,
  # exactly once -- so "this playthrough's copy of the ward stamp" always names
  # the world's ward stamp and never another game's.
  def a_template_is_a_template
    return if template_id.nil?

    errors.add(:template, "is only for a playthrough's own copy; the world's own rows copy nothing") if template?
    errors.add(:template, "must be one of the world's own rows, not another playthrough's copy") if template&.instance?
  end

  # THE COLUMN OR THE OBJECT IN FRONT OF IT. An item built through the owner's
  # association -- `location.items.build(...)`, which autosave validates before
  # the parent has an id -- has the owner in memory and nothing in the column
  # yet, and reading only the column called that item nowhere. The association's
  # target is read directly so a set id costs no query.
  def occupies?(place)
    return true if self[place].present?

    association(place.to_s.delete_suffix("_id").to_sym).target.present?
  end
end
