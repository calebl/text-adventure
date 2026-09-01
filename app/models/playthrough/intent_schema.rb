# What one line of player input was aimed at: an intent from a fixed set, and
# which of the things actually in front of the player it was pointed at.
#
# This is a FACTORY rather than a schema class, and that is the whole design.
# `target` is an enum built per call from the exits out of this room, the people
# standing in it, the items lying in it and the items the player is carrying --
# a set the app knows exactly, and the one answer the game loop cannot afford a
# paraphrase of. `Playthrough::Classifier` has to turn the answer back into a
# `Location`, a `Character` or an `Item` record; "north" and "the woman by the fire" resolve
# to nothing, and a fuzzy matcher written to cope with them would be guessing
# on the seam that moves the player and decides what they are carrying. Closing
# the set means the model either names something that exists or names NOTHING,
# and there is no third answer.
#
# `intent` is a fixed table for the same reason every enum here is
# (`LocationConnection::DISTANCES`, `Character.sexes`): five words in, five
# words out, no prose to parse.
class Playthrough::IntentSchema
  # What a player can be trying to do. `move`, `talk`, `take` and `drop` are the
  # four the game loop acts on -- each resolves to a record and each writes one.
  # `take` and `drop` are BOTH here and that is not symmetry for its own sake:
  # an app that owns picking up but leaves putting down to the narrator has
  # records that go stale the first time a player sets something on a table.
  # Both directions, or neither is real. `examine` and `other` are told apart so
  # the narrator knows what it is answering and so inspection has a seam to land
  # in later.
  INTENTS = %w[move talk examine take drop other].freeze

  # The answer for "the player did not name anything on either list". Needed
  # because `strict` schemas make every property required, so `target` has to
  # have something to say when there is nothing to point at.
  NOTHING = "nothing".freeze

  # `targets` is the exit names, the names and nicknames of whoever is here, the
  # names of what is lying here and the names of what the player is carrying.
  # Blank and duplicate entries are dropped: JSON Schema enums must be unique,
  # an empty string is not a name, and a thing the player is holding while
  # another of the same name lies on the floor is one entry.
  def self.for(targets)
    choices = Array(targets).map(&:to_s).map(&:strip).reject(&:empty?).uniq + [ NOTHING ]

    RubyLLM::Schema.create do
      name "player_intent"

      string :intent,
             description: "What the player is trying to do. Pick the closest.",
             enum: INTENTS
      string :target,
             description: "What they aimed it at, copied exactly from the lists you were given: a way out for `move`, a person for `talk`, a thing lying here for `take`, a thing they are carrying for `drop`. Answer `#{NOTHING}` for anything else, or when they named something that is not on those lists.",
             enum: choices
    end
  end
end
