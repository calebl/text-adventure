# WHERE MONSTERS COME FROM, and the only place in the app that decides it.
#
# THE CAPTAIN'S SEVENTH RULING, 2026-09-04 evening: a generated character whose
# race is monstrous is hostile by default, and *where* monsters appear is a
# rolled per-room **danger** parameter in the shape of `locations.mobile` and
# `location_connections.distance` -- seeded for a hand-authored world, rolled by
# the engine when a room is born in a generated one, and a dangerous room draws
# its inhabitants from the universe's monstrous races instead of its peoples.
#
# TWO ROLLS, AND THEY HAPPEN AT DIFFERENT MOMENTS. That is the whole of this
# module:
#
#   `.for_a_new_room`  what a room IS, thrown once when it comes into existence
#                      -- `Location::Generator#create_stub!`, because a stub is
#                      a room being born. A seeded room is not rolled at all:
#                      the file is the decision, exactly as it is for `mobile`
#                      and for `characters[].stats`.
#                      THE OPENING ROOM OF A GENERATED WORLD IS NOT ROLLED and
#                      is therefore safe: `Story::Generator` builds it in the
#                      same unsaved graph as the story, before there is an id to
#                      seed from -- and a player should not open a game standing
#                      in a room the world filled with its monsters.
#   `.monstrous?`      whether ONE person about to be written into that room is
#                      one of its monsters, thrown per slot at realization out
#                      of a generator `Character::Registry#slots` holds for the
#                      whole call.
#
# WHAT A GENERATED WORLD ACTUALLY PRODUCES TODAY, said out loud so nobody is
# surprised by it: NO MONSTERS. `Universe::Generator` writes a race list and
# never marks one `monstrous`, so a generated world's bestiary is empty and a
# dangerous room in it falls back to the peoples (`Character::Registry#race_from`
# -- an empty pool writes an ordinary person rather than nobody). Everything
# below is live and rolled; what it has nothing to draw from is the half the
# captain's standing intent covers -- *"eventually I want the universe generator
# to provide more input into this"* -- and that is a later slice, deliberately
# not built here. A HAND-AUTHORED world is monstrous today, which is what
# `db/seeds/worlds/the-lunar-cartographer.yml` is for.
#
# `ROLLED` IS NARROWER THAN `Location::DANGERS`, on purpose. The engine draws
# one of these; `deadly` is a word only a seed file may say, because a room
# where every inhabitant is a monster is a decision somebody made about a world
# rather than a thing a die should be able to do to one. The list IS the
# weighting -- `Roll.one_of` draws one entry, so a key written twice is twice as
# likely -- which is `Character::HIT_DICE`'s shape rather than a second table of
# probabilities to keep in step with the first.
#
# WHY THE SEQUENCE IS OFFSET. `Roll.seed` is four integers and one of them says
# which roll within a story moment (`Roll`'s header). A danger roll and a stat
# block rolled for the same story at the same moment would otherwise be the same
# number twice, because both key on small sequence numbers. `SEQUENCE_BASE`
# moves every roll in this file into a range nothing else in the app reaches --
# no story has a million rooms and no story has a million people -- so the two
# streams cannot collide. It is plain integer arithmetic, which is the one thing
# about `Roll` that must not be "simplified".
module Location::Danger
  # WHICH ROLL THIS IS: not a body's. See the header.
  SEQUENCE_BASE = 1_000_000

  # WHAT A ROOM BORN IN A GENERATED WORLD MAY COME OUT AS, and the list is the
  # weighting. Five in eight rooms are safe, two are uneasy, one is dangerous --
  # so a player walking a generated world meets the world's monsters
  # occasionally rather than constantly, and `Character::Registry`'s "nobody is
  # the ordinary answer" is still true of most rooms.
  ROLLED = [
    Location::SAFE, Location::SAFE, Location::SAFE, Location::SAFE, Location::SAFE,
    "uneasy", "uneasy",
    "dangerous"
  ].freeze

  # WHAT A ROOM IS, thrown once as it comes into existence. Keyed on the story,
  # where its clock stood and how many rooms it already had, which is
  # `Character::StatBlock.for_new`'s seed with this file's own sequence base:
  # two rooms born out of one realization are two rolls rather than one number
  # twice, and the answer is the same in any process for ever.
  def self.for_a_new_room(story)
    rng = Roll.generator(story: story.id, at: story.clock.to_i,
                         sequence: SEQUENCE_BASE + story.locations.count)

    Roll.one_of(ROLLED, rng: rng)
  end

  # THE GENERATOR ONE ROOM'S CAST IS DRAWN FROM. Handed out rather than kept, on
  # `Roll`'s standing rule: a caller throwing several dice for one decision
  # throws them from one seed in one order, so the people this realization
  # writes are decided together and re-derivably. Keyed on the room's own id
  # rather than on the clock, because a room is realized once and its id is the
  # durable thing about it.
  def self.generator_for(location)
    Roll.generator(story: location.story_id, sequence: SEQUENCE_BASE + location.id.to_i)
  end

  # WHETHER THE NEXT PERSON WRITTEN INTO THIS ROOM IS ONE OF THE WORLD'S
  # MONSTERS. `danger_share` faces of `DANGER_DIE`, and at a share of zero NO
  # DIE IS THROWN AT ALL -- `Character::Check`'s rule at an impossible target,
  # and here for the same two reasons: the answer is false for ever, and a room
  # that asks the impossible must not consume the next slot's roll.
  def self.monstrous?(location, rng:)
    share = location.danger_share
    return false unless share.positive?

    Roll.die(Location::DANGER_DIE, rng: rng) <= share
  end
end
