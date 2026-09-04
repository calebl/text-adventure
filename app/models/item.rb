# A thing in the world, and WHERE IT IS is the whole of what this class is for.
#
# Exactly one of THREE places (`PLACES`), never two of them and never none:
#
#   `location`     it is lying in a room, which is what makes it takeable.
#                  Story-level and shared between playthroughs of one world,
#                  deliberately: the rooms are the world.
#   `character`    one of the world's OWN people is holding it. For the
#                  PROTAGONIST that is the story's STARTING INVENTORY -- world
#                  data, written by the seed file, exported by the exporter,
#                  copied to a playthrough when one begins, and carried by
#                  nobody. See `Story#starting_inventory`.
#   `playthrough`  THE PARTY OF ONE PLAYTHROUGH IS CARRYING IT. This is the
#                  app's answer to "does the player have this", and the only
#                  answer -- see `Playthrough::Turn#take_item`.
#
# THE THIRD COLUMN IS THE POSITION SHAPE, and the argument is PR 109's word for
# word. Where the player STANDS is `playthroughs.current_location_id` and not a
# column on the protagonist, because two people playing one seeded world stand
# in two rooms at once. They also carry two different sets of things: with the
# inventory on `items.character_id`, playthrough 17 of a story opened holding
# what playthrough 16 had picked up. `Playthrough#carried` is the one reader
# and `Playthrough::Turn#carry!` / `#put_down!` the only writers.
#
# `location` IS WHAT MADE `take` POSSIBLE TO OWN. With items only ever in
# somebody's hands there was nothing on the floor to pick up, so taking could
# only be a sentence the narrator wrote and the game had no record either way.
# Now `Playthrough::Classifier` resolves `take` against the items the records
# say are lying in this room, and the app moves the row.
#
# HOW ITEMS COME TO EXIST is `Item::Registry`, and it is the only thing in the
# app that creates one: a room's furniture is written as structured records the
# moment the room is realized, out of the same call that describes it, exactly
# the way its exits are. Not by reading narration and not through a tool the
# narrator may or may not call -- read that class's header for why the
# distinction is the whole point. This class still only answers WHERE the ones
# that exist are; a seed file is now one writer of them among two.
#
# AND WHAT IS WRITTEN ON IT, for the things that have writing on them. A note, a
# letter, a sign, a label: `readable` says the thing has words on it and
# `inscription` holds them, so what a note says is a record the engine owns
# rather than a sentence the narrator improvised and nothing kept. It is the
# same argument `items.playthrough_id` settles for possession, one column
# further on: a fact the game depends on, held in a paragraph, is a fact that
# drifts. It is orthogonal to WHERE the thing is -- all three of `PLACES` keep
# their text, because writing belongs to the note and not to the shelf. The
# words reach the prose through `Playthrough::Turn#read_fact`, verbatim and
# stated; `Item::Inscriber` writes them once for a readable thing that arrived
# without any, and never again.
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
  belongs_to :playthrough, optional: true

  validates :name, presence: true
  validates :description, presence: true
  validates :inscription, length: { maximum: INSCRIPTION_LIMIT }
  validate :in_exactly_one_place
  validate :inscription_requires_readable

  # WHAT ONE OF THE WORLD'S OWN PEOPLE IS HOLDING, which since the party's
  # inventory moved to the playthrough is no longer what the player has. Asked
  # of the protagonist it answers the story's starting inventory; asked of
  # anybody else, that person's possessions. Neither is in a closed set.
  scope :for_character, ->(character) { where(character: character) }
  scope :by_name, ->(name) { where(name: name) }

  # THE CLOSED SET `take` RESOLVES AGAINST: what is lying in this room. Items
  # in somebody's hands are excluded on purpose -- taking something off a
  # person is a different act with somebody on the other side of it, and there
  # is no record of how they feel about it. So are the ones a party is carrying:
  # a row astray in two places at once (which `#in_exactly_one_place` refuses to
  # save and `rake game:doctor` reports) must not be offered as takeable.
  scope :lying_in, ->(location) { where(location: location, character_id: nil, playthrough_id: nil) }

  # Held by one of the world's own people, anywhere in any story.
  scope :held, -> { where.not(character_id: nil) }

  # THE CLOSED SET `drop` RESOLVES AGAINST: what this playthrough's party is
  # carrying. Read through `Playthrough#carried` rather than here -- one reader,
  # for the same reason `Character.present_in` has one.
  scope :carried_by, ->(playthrough) { where(playthrough: playthrough) }

  # Carried by any party at all, the inverse of `carried_by` across the board.
  scope :carried, -> { where.not(playthrough_id: nil) }

  # EVERY ITEM IN ONE STORY, on whichever of the three sides of the one-place
  # rule it sits. There is no `items.story_id` -- an item is reached through
  # whoever has it -- so this is the three queries that answer for a story, and
  # it is the one place they are written: `Item::Registry`, `Character::Registry`,
  # `Story::Doctor`, `EngineSweep::Invariants` and `WorldSeed::Loader` all read
  # it here, because a leg missing from one copy is an item the caps cannot see.
  scope :in_story, ->(story) {
    where(character_id: story.characters.select(:id))
      .or(where(location_id: story.locations.select(:id)))
      .or(where(playthrough_id: story.playthroughs.select(:id)))
  }

  # THE THINGS WITH WORDS ON THEM. It cuts across all three places: a note lying
  # in a room, a note in an NPC's hands and a note a party is carrying all keep
  # their text, because what is written on a thing is a fact about the thing and
  # not about where it is. Nothing in the app generates text for an item outside
  # this scope -- see `Item::Inscriber`.
  #
  # A row-level question everywhere it matters -- `#readable?` on the record the
  # classifier resolved -- so this is the set query, for a report about a whole
  # world. `#unwritten` is the one worth asking: a readable thing nobody has read
  # is not a defect (the first read writes it), so no instrument reports it, and
  # what a person actually wants to know is which notes hold words yet.
  scope :readable, -> { where(readable: true) }
  scope :unwritten, -> { readable.where(inscription: nil) }

  def held? = character_id.present?

  def lying? = character_id.nil? && playthrough_id.nil? && location_id.present?

  def carried? = playthrough_id.present?

  # There is something written on this AND the records hold it. The two halves
  # are separate on purpose: `readable?` is what the world says about the thing,
  # `inscribed?` is whether anybody has written the words down yet, and only the
  # second is what `Playthrough::Turn#read_fact` can quote.
  def inscribed? = readable? && inscription.present?

  # Where it is, in one sentence, for a report a person reads.
  def whereabouts
    return "held by #{character.fullname}" if held?
    return "carried by playthrough ##{playthrough_id}" if carried?
    return "lying in #{location.name}" if lying?

    "nowhere"
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

  private

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
  # It says NOTHING ABOUT WHERE THE THING IS, deliberately: what is written on a
  # note is a fact about the note, so all three of `PLACES` keep it, and a copy
  # made for a playthrough's starting inventory copies the words with everything
  # else (`Playthrough#take_up_the_starting_inventory`).
  def inscription_requires_readable
    return if inscription.blank? || readable?

    errors.add(:inscription, "cannot be written on something that is not readable")
  end

  # EXACTLY ONE OF THE THREE, and the two failures are different facts.
  #
  # Two at once is the state that would make `take` unanswerable: an item a
  # party is carrying that is also on the floor is takeable and already taken.
  # None at all is an item nowhere, which no closed set can ever offer.
  #
  # The message names the columns rather than the fiction because the reader is
  # whoever wrote the row -- a seed file, a registry, a backfill. The constant is
  # public because `Story::Doctor` and `EngineSweep::Invariants` count the same
  # three columns on rows raw SQL or an older schema could have left astray.
  PLACES = %i[character_id location_id playthrough_id].freeze

  def in_exactly_one_place
    occupied = PLACES.select { |place| occupies?(place) }
    return if occupied.one?

    if occupied.empty?
      errors.add(:base, "must be lying in a location, held by a character or carried by a playthrough")
    else
      errors.add(:base, "is in #{occupied.size} places at once (#{occupied.join(", ")}); it may only be in one")
    end
  end

  # THE COLUMN OR THE OBJECT IN FRONT OF IT. An item built through the owner's
  # association -- `playthrough.items.build(...)`, which autosave validates
  # before the parent has an id -- has the owner in memory and nothing in the
  # column yet, and reading only the column called that item nowhere. The
  # association's target is read directly so a set id costs no query.
  def occupies?(place)
    return true if self[place].present?

    association(place.to_s.delete_suffix("_id").to_sym).target.present?
  end
end
