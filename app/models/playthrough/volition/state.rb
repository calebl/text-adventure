# THE ROOM AND THE PEOPLE IN IT, WRITTEN OUT AS RECORDS A TYPED QUESTION CAN
# POINT AT.
#
# `Playthrough::Classifier::State`'s shape, one decision over: the room by
# name, one entry per record under a key the answers come back naming, and the
# line the player typed LAST. A System One reader answers from the state it is
# sent and from nothing else, so a request that states two ids and asks how
# pressured somebody is has asked a question its own state cannot answer.
#
# WHAT EACH PERSON CARRIES, and every value is a record the engine already
# holds: the name they answer to, the six desire columns
# (`Character::Desires`), and what they witnessed in this game
# (`Playthrough::Ledger#recall`) -- the engine's own `fact` sentences, bounded
# by that class's own two limits, so a long game costs the same per call.
#
# THE ACTS ARE THE CLOSED SET AND NOTHING ELSE. They come out of
# `Playthrough::Volition#choices`, whose sentences were written for exactly
# this, and they are sent under stable labels (`act_1`, `act_2`, ...) rather
# than as tokens, for the reason the classifier's keys are `way_1` rather than
# ids: a token carries a row id, and a request whose bytes move with a row id
# is a request no fixture can pin. `#token_for` is the one way back, and a
# label this state never offered resolves to nil. The token that comes back is
# then applied through `Playthrough::Volition#apply!`, which rebuilds the set
# and rejects anything no longer in it -- that check is untouched.
#
# KEY ORDER IS PART OF THE REQUEST. `player_action` is last, a person with no
# witnessed facts sends an empty list rather than no key, and a blank desire
# column is sent as an empty string: an absent key says nothing, a present
# empty one says "none". `Playthrough::Volition::StateTest` pins the bytes.
class Playthrough::Volition::State
  DESIRES = %w[conscious_desire unconscious_desire recognized_need unrecognized_need
               desire_pursuit need_pursuit].freeze

  attr_reader :playthrough, :characters, :location, :line

  def initialize(playthrough, characters, location:, line: nil)
    @playthrough = playthrough
    @characters = characters
    @location = location
    @line = line
  end

  def to_h
    {
      "location" => location.name.to_s,
      "characters" => people.to_h { |person| [ person.key, entry_for(person) ] },
      "player_action" => line.to_s
    }
  end

  # One per character, in the order they were handed in (`Volition.run!`
  # hands them in `id` order).
  Person = Data.define(:key, :character, :acts)

  def people
    @people ||= characters.each_with_index.map do |character, offset|
      choices = Playthrough::Volition.new(playthrough, character, location: location).choices
      acts = choices.each_with_index.to_h { |(token, sentence), index| [ "act_#{index + 1}", [ token, sentence ] ] }
      Person.new(key: "person_#{offset + 1}", character: character, acts: acts)
    end
  end

  # The labelled acts one person may be answered with, label => sentence.
  def criteria_for(person) = person.acts.transform_values(&:last)

  # WHAT AN ANSWER'S LABEL MEANS: the token it stood for when this state was
  # built, or nil for a label it never offered.
  def token_for(person, label) = person.acts[label.to_s]&.first

  private

  def entry_for(person)
    character = person.character
    entry = { "name" => character.fullname.to_s }
    DESIRES.each { |column| entry[column] = character.public_send(column).to_s }
    entry["witnessed"] = Playthrough::Ledger.new(playthrough, character).recall(location: location)
    entry
  end
end
