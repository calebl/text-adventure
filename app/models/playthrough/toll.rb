# WHAT ONE HAZARD TOOK OFF ONE BODY IN ONE GAME, and the durable record of it.
#
# THE `Playthrough::Blow` OF A PLACE, and it is a separate table for two
# reasons rather than a preference:
#
#   A HAZARD HAS NO ATTACKER. `playthrough_blows.attacker_id` is NOT NULL and
#   `Playthrough::Turn#damage_for` is one die of the attacker's `hit_die`; the
#   tide has no hit die, cannot be swung back at, and cannot be killed. A row
#   in that table would need a fictional body to point at.
#
#   AND THE FIGHT-END RULE MUST NOT TREAT A HAZARD AS A FOE.
#   `Playthrough::Fight#open_blows` is *the fight that is still on*, so a hazard
#   written as a blow would OPEN a fight nobody was in -- and `#over?` would
#   close it on the same turn, writing a `Scene` into the column
#   `Story::Audit` and `Eval::Richness` read, saying a fight had ended that
#   never began. A room that hurts you is not somebody fighting you.
#
# What the two records DO share is the one writer: every hit point in this app
# comes off through `Playthrough::Turn#harm!`, whatever took it. That is §8.1 of
# `data/ta-combat-scout/report.md` -- one writer, several named sources -- and
# it is why a hazard can kill and end a game exactly as a blow does, with no
# second copy of the statement that ends one.
#
# THIS GAME'S SIDE OF THE LAYER SPLIT, like `Playthrough::Vitals` and
# `Playthrough::Blow`: the WORLD says the tide post floods and how hard
# (`locations.hazard`, `locations.hazard_die`, written by a seed file and by no
# model and no typed line), and a GAME says who was standing in it and what it
# cost them.
#
# EVERY COLUMN IS THE ENGINE'S OWN ANSWER and no prompt mentions any of them.
class Playthrough::Toll < ApplicationRecord
  self.table_name = "playthrough_tolls"

  belongs_to :playthrough
  belongs_to :character
  belongs_to :location
  # THE DOORWAY, WHEN IT WAS A DOORWAY'S -- the ONE DIRECTED ROW that was
  # walked. Nil for a room's own hazard, and that nil is the whole of what tells
  # the two sources apart on the row.
  belongs_to :location_connection, optional: true
  # THE SCENE THAT TOLD THE PLAYER ABOUT IT. Nil is "the prose has not said this
  # yet" -- `Playthrough::Blow#scene_id` read for the other thing that hurts.
  belongs_to :scene, optional: true

  validates :hazard, presence: true
  validates :damage, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :hp_after, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :story_timestamp, presence: true
  # NEGATIVE, AND THAT IS THE POINT -- see `.next_sequence`.
  validates :sequence, presence: true, numericality: { only_integer: true, less_than: 0 }

  # Oldest first, on `id`, which is the ordering every other closed set in this
  # app is read in.
  scope :chronological, -> { order(:id) }

  # THE ROWS NO SCENE HAS TOLD THE PLAYER ABOUT: what `Playthrough::Moment`
  # states as a fact, once. `Playthrough::Blow.open`'s shape, named for what nil
  # means here -- a toll is not "open" the way a fight is, because nothing about
  # it is still going on.
  scope :untold, -> { where(scene_id: nil) }

  # WHICH ROLL OF THIS GAME THE NEXT TOLL IS, OUT OF A RECORD, AND IT COUNTS
  # DOWNWARDS.
  #
  # `Roll`'s seed is (story, playthrough, story clock, sequence) and the fourth
  # is which roll within that moment -- so two rolls at one story moment must
  # not share it. Three things roll at a moment now: `Playthrough::Turn#check`
  # uses 1..`Character::ABILITIES.size`, `Playthrough::Blow` uses
  # `SEQUENCE_OFFSET` upwards off its own count, and this. A hazard and a blow
  # DO land at one moment -- step 7 runs the riposte and then the every-turn
  # hazard -- so the two need keeping apart.
  #
  # NEGATIVE IS HOW, and it is the cheapest correct answer: the tolls count down
  # from -1 while the checks and the blows count up, so the two spaces cannot
  # meet however many of either a game accumulates. An offset cannot do it --
  # both counts are unbounded -- and coupling the two tables' counts would make
  # a blow's die depend on how much weather a game had walked through.
  #
  # OFF THE ROWS AND NOT OFF A COUNTER, for `Playthrough::Blow.next_sequence`'s
  # reason: a number in memory does not survive the process that held it, and a
  # walk replayed in a second process has to throw the same dice or
  # `rake game:sweep` could not assert what one did.
  def self.next_sequence(playthrough) = -(where(playthrough: playthrough).count + 1)

  # WHETHER THE BODY GOT CLEAR OF IT. A column and not `damage.zero?`, because a
  # `save: nil` hazard rolls no d20 at all and a die that came up 1 damage is
  # not a save -- two different facts that one number would collapse.
  def saved? = saved

  def killed? = hp_after.zero?

  # WHAT TOOK IT, in the app's own words, out of the table the key belongs to.
  # A doorway's hazard reads out of `LocationConnection::HAZARDS` and a room's
  # out of `Location::HAZARDS`; the row says which by whether it carries an edge.
  #
  # AND IT FALLS BACK TO THE OTHER TABLE, because the edge can go: a doorway is
  # deleted and rewritten by `WorldMechanic::ShuffleConnections` in the ordinary
  # course of a world moving, and `location_connection_id` is nullified when it
  # does. A toll that then read only the room's catalogue would print a bare key
  # where it used to print a sentence. The two catalogues share no key, so the
  # order only decides which is asked first.
  def entry
    tables = location_connection_id.present? ?
      [ LocationConnection::HAZARDS, Location::HAZARDS ] : [ Location::HAZARDS, LocationConnection::HAZARDS ]

    tables.filter_map { |table| table[hazard] }.first
  end

  # The catalogue's own sentence about it, or the bare key for a row whose key
  # the table no longer has -- the honest nothing, rather than a blank.
  def words = entry&.fetch(:words) || hazard

  # WHERE IT WAS PAID, as a phrase. A doorway names both ends and the direction,
  # because a one-way hazard's whole content is which way you were going.
  def where_it_was
    return location.name if location_connection.nil?

    "the way from #{location_connection.location.name} into #{location_connection.connected_location.name}"
  end

  def condition
    Playthrough::Vitals::Condition.new(character: character, hp: hp_after, max: character.max_hp)
  end

  # For the `rake game:mechanics` read-out and for a sweep's `note:`. The
  # numbers, because a number is a fact where "badly" is a mood -- the rule
  # `Playthrough::Blow#to_s` is written under.
  def to_s
    return "#{character.fullname} got clear of #{hazard} on #{where_it_was}" if saved?

    "#{hazard} on #{where_it_was} cost #{character.fullname} #{damage} hit " \
      "point#{"s" unless damage == 1} (#{words}); #{character.fullname} is #{condition.in_words}"
  end
end
