# THE FIRST CONTACT THAT WRITES A VITALS ROW, and the only thing in the app that
# creates one outside `Playthrough::Turn#harm!`.
#
# THE ITEM HALF IS `Item::Snapshot` AND THIS IS THE PEOPLE HALF, at the same
# moment and for the same reason. The captain's ruling of 2026-09-04 gives every
# playthrough its own copy of what the world holds; a body's condition is that
# copy for a person. So the trigger is identical -- the room the party is
# standing in at the top of every turn, the room they have just walked into
# after it is realized, and the party itself when the playthrough is created --
# and `Playthrough::Snapshot` is the seam that calls both, so neither can be
# taken without the other.
#
# LAZY, AND WHY IT MATTERS MORE HERE THAN FOR ITEMS. A world generates itself
# for as long as somebody keeps walking, so a game that instantiated every
# person up front would write rows for people who do not exist yet. And the
# absent row is not merely deferred work: it MEANS unhurt
# (`Playthrough::Vitals`), so a game that never meets Rowe never writes anything
# about Rowe, which is the truth.
#
# IT IS IDEMPOTENT BY THE UNIQUE INDEX rather than by a guard of its own:
# `Playthrough::Vitals.instantiate!` is `find_or_create_by!` on the pair the
# index is on. The item snapshot needs a per-template guard because a copy has
# no natural key; a body does -- it is that character, in that game, once.
#
# NOBODY WITH NO STAT BLOCK GETS A ROW. `Playthrough::Vitals.instantiate!`
# returns nil for them, because there is no maximum to start them at and
# inventing one is what `characters.level` is nullable to avoid.
# `rake game:doctor` reports the person; nothing here quietly repairs them.
#
# NO MODEL, NO NETWORK, NO GENERATION. Every row it writes is derived from a
# stat block that already exists.
class Playthrough::Vitals::Snapshot
  attr_reader :playthrough

  def initialize(playthrough)
    @playthrough = playthrough
  end

  # THE PEOPLE STANDING IN A ROOM, out of `Character.present_in` -- the same
  # closed set `talk` resolves against and the same one `Item::Snapshot` reads
  # to copy what is in their hands. Nil is a no-op: a playthrough standing
  # nowhere is standing with nobody.
  def of_the_room!(location)
    return [] if location.nil?

    Character.present_in(location).filter_map { |person| instantiate(person) }
  end

  # THE PARTY: the protagonist, whose body is the one that can end the game.
  # Companions are deliberately NOT here -- they are wherever the playthrough is
  # rather than in a room (`Character`'s header), so nothing in this PR can hurt
  # one, and writing a row saying "nothing has happened" for each of them would
  # be writing the default down.
  def of_the_party!
    [ instantiate(playthrough.story&.protagonist) ].compact
  end

  private

  def instantiate(character)
    Playthrough::Vitals.instantiate!(playthrough, character)
  end
end
