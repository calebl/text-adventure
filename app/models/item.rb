# A thing in the world, and WHERE IT IS is the whole of what this class is for.
#
# Exactly one of two places, never both and never neither:
#
#   `character`  somebody is holding it. The protagonist holding it is the
#                app's answer to "does the player have this", and the only
#                answer -- see `Playthrough::Turn#take_item`.
#   `location`   it is lying in a room, which is what makes it takeable.
#
# The second half is new and it is what made `take` possible to own. With items
# only ever in somebody's hands there was nothing on the floor to pick up, so
# taking could only be a sentence the narrator wrote and the game had no record
# either way. Now `Playthrough::Classifier` resolves `take` against the items
# the records say are lying in this room, and the app moves the row.
#
# HOW ITEMS COME TO EXIST is `Item::Registry`, and it is the only thing in the
# app that creates one: a room's furniture is written as structured records the
# moment the room is realized, out of the same call that describes it, exactly
# the way its exits are. Not by reading narration and not through a tool the
# narrator may or may not call -- read that class's header for why the
# distinction is the whole point. This class still only answers WHERE the ones
# that exist are; a seed file is now one writer of them among two.
class Item < ApplicationRecord
  belongs_to :character, optional: true
  belongs_to :location, optional: true

  validates :name, presence: true
  validates :description, presence: true
  validate :in_exactly_one_place

  scope :for_character, ->(character) { where(character: character) }
  scope :by_name, ->(name) { where(name: name) }

  # THE CLOSED SET `take` RESOLVES AGAINST: what is lying in this room. Items
  # in somebody's hands are excluded on purpose -- taking something off a
  # person is a different act with somebody on the other side of it, and there
  # is no record of how they feel about it.
  scope :lying_in, ->(location) { where(location: location, character_id: nil) }

  # Held by anybody at all, which is the inverse of `lying_in` across the board.
  scope :held, -> { where.not(character_id: nil) }

  def held? = character_id.present?

  def lying? = character_id.nil? && location_id.present?

  # Where it is, in one sentence, for a report a person reads.
  def whereabouts
    return "held by #{character.fullname}" if held?
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

  # Both at once is the state that would make `take` unanswerable: an item
  # somebody is holding that is also on the floor is takeable and already
  # taken. Neither is an item nowhere, which no closed set can ever offer.
  def in_exactly_one_place
    return if character_id.present? ^ location_id.present?

    if character_id.present?
      errors.add(:location, "must be empty while somebody is holding this")
    else
      errors.add(:base, "must be held by somebody or lying in a location")
    end
  end
end
