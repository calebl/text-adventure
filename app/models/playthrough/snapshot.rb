# WHAT A GAME COPIES OUT OF THE WORLD WHEN IT FIRST STANDS IN FRONT OF IT, and
# the one seam that takes it.
#
# There are two things a playthrough owns its own copy of -- what is lying in a
# room (`Item::Snapshot`) and how much is left of a body
# (`Playthrough::Vitals::Snapshot`) -- and they are copied at the same five
# moments for the same reason: the captain's ruling of 2026-09-04 that a
# playthrough owns the instance of whatever the world holds the template of.
#
# THIS EXISTS SO THERE IS ONE CALL AND NOT TWO. Five call sites take the
# snapshot: `Playthrough#take_up_the_opening_snapshot`,
# `Playthrough::Turn#play`, `Playthrough::Turn#move_to`,
# `Playthrough::Mechanics#run` and `#stand_in`. Ten statements across five
# places is nine chances to add a third thing and forget one of them, and the
# failure it would produce is silent: a room whose things this game has copied
# and whose people it has not.
#
# It holds no state of its own and makes no model call. Both halves are
# idempotent, so calling it twice on one room is the second one doing nothing.
class Playthrough::Snapshot
  attr_reader :playthrough

  def initialize(playthrough)
    @playthrough = playthrough
    @items = Item::Snapshot.new(playthrough)
    @vitals = Playthrough::Vitals::Snapshot.new(playthrough)
  end

  # A room and the people standing in it: what is lying here, what is in their
  # hands, and how much is left of them.
  def of_the_room!(location)
    { items: @items.of_the_room!(location), vitals: @vitals.of_the_room!(location) }
  end

  # What the story starts the player holding, and the body they start in.
  def of_the_party!
    { items: @items.of_the_party!, vitals: @vitals.of_the_party! }
  end
end
