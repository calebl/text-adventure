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

  # WHAT ONE LINE CAN NAME AND STILL BE ANSWERED. `target` is one value,
  # because a turn is one act: `Playthrough::Turn#play` branches once, writes
  # once and narrates once. So "pick up the index and the apron" has an answer
  # this cannot hold, and what used to happen is that the model picked one, the
  # loop took it, and the other half of the sentence went nowhere -- no record,
  # no refusal, and nothing counted it either, because the reach DID resolve
  # and so no `Playthrough::Drift` row was written.
  #
  # `also_named` is that other half, said out loud. It is NOT a second target
  # and nothing acts on it: it is one more name out of the same closed set, so
  # the app can say what it is not doing instead of dropping it silently.
  #
  # ONE name and not a list, deliberately. An array would have to be allowed to
  # come back empty, and an empty required array reads as an omitted field to
  # `BaseAgent#missing_schema_keys` -- which would fail the commonest call in
  # the app on the commonest answer. `nothing` is a value this enum already
  # has. The cost is that a line naming three things reports one of the two it
  # skipped; the count of lines that overreached is still exact, and that is
  # the number worth having.
  #
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
      string :also_named,
             description: "One more thing on those lists that the player named in the SAME line and that `target` is not already pointing at, copied exactly -- as in \"take the index and the apron\". One line does one thing, so nothing here is acted on; naming it is only how the game says what it is leaving undone. Answer `#{NOTHING}` when they named one thing or none, which is usual.",
             enum: choices
    end
  end
end
