# THE WORLD'S HALF OF A ROUND: every live foe in the room acts, in `id` order.
#
# THE CAPTAIN'S CALL C5, and it is the whole design: A ROUND IS THE TURN. The
# player acts by typing; then this runs. There is no initiative system to build
# and building one would be building a second clock -- the loop is one typed
# line per turn and story time advances per turn, so an ordering of at most two
# monsters (`Character::Registry::MAX_PER_ROOM` is 3) is the whole of what an
# initiative roll would buy. `id` order is the app's own answer to "in what
# order do two records in one room come out" (`Character.present_in`,
# `Item.lying_in`), reused rather than reinvented.
#
# IT RUNS ON A TURN THE PLAYER SPENT DOING SOMETHING ELSE, and that is the
# point: it is what makes a fight a fight. You can look at the ceiling and the
# hound still bites. Two consequences, both stated rather than discovered:
#
#   A REFUSED LINE MEANS THE FOES DO NOT ACT. *"A refused line writes nothing"*
#   is the captain's ruling of 2026-09-04 and a foe acting would write
#   something, so `Playthrough::Turn#play` and `Playthrough::Mechanics#run` both
#   run this only on a line they PLAYED.
#
#   ON A MOVE, THE FOES IN THE ROOM YOU LEFT ACT BEFORE YOU GO. You turned your
#   back. The caller passes the room it was standing in when the turn began, so
#   a move out of a fight costs one more exchange and then the fight is over
#   (`Playthrough::Fight`) -- which is the captain's call C1, *a fight is always
#   escapable by leaving the room*, with a price on it.
#
# IT MAKES NO MODEL CALL AND HOLDS NO COPY OF A WRITER. Every blow goes through
# `Playthrough::Turn#strike!`, which is the one writer of `playthrough_blows`
# and reaches `#harm!` for the hit points -- the same rule `Playthrough::Mechanics`
# is under, and for its reason: a second copy of the statement that hurts
# somebody would be testing itself.
class Playthrough::Riposte
  attr_reader :playthrough, :turn

  def initialize(playthrough, turn: nil)
    @playthrough = playthrough
    @turn = turn || Playthrough::Turn.new(playthrough)
  end

  # Every live foe in `location` strikes the party once, in `id` order. Returns
  # the `Playthrough::Blow` rows it wrote, oldest first; an empty list is the
  # ordinary turn, in the ordinary room, with nobody hostile in it.
  #
  # IT STOPS THE MOMENT THE PLAYER IS DEAD. A game that is over is a game
  # nothing will ever change again (`Playthrough#over?`), so the second hound
  # does not get to bite a corpse.
  def run!(location:, round:)
    target = playthrough.character
    return [] if location.nil? || target.nil? || playthrough.over?

    blows = []

    playthrough.foes_in(location).each do |foe|
      break if playthrough.over?

      blow = turn.strike!(foe, target, round: round, room: location)
      blows << blow if blow
    end

    blows
  end
end
