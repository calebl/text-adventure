# THE WORLD'S OTHER HALF OF A ROUND: the place you are standing in, and the way
# you got into it.
#
# The captain's request, second half -- *"certain terrain or actions should also
# cause damage"* -- and §8 of `data/ta-combat-scout/report.md`. It is the same
# design `Playthrough::Riposte` is: something that is not the player takes a
# turn's worth of action, through the ONE writer of a hit point
# (`Playthrough::Turn#harm!`) and holding no copy of it, so a hazard that kills
# ends the game by the same statement a blow does and there is no second place
# a playthrough can end.
#
# THERE ARE EXACTLY TWO BRANCHES AND THEY ARE NAMED, which is the point.
# `data/ta-direction/report.md` §12 rules out *"a general rule language,
# predicate DSL, or condition evaluator"* and §8.4 rules out an "action carries
# a consequence" table by name. What is here instead is two methods:
#
#   #on_arrival!   THE DOORWAY, THEN THE ROOM, in that order because that is the
#                  order they happen in: you cross and then you are standing
#                  there. Called from `Playthrough::Turn#move_to` after the room
#                  is realized and after `Playthrough::Snapshot` -- so the world
#                  exists and this game has its copy of it before anything can
#                  cost anybody anything -- and from `Playthrough::Mechanics`'s
#                  offline move in the same place for the same reason.
#   #every_turn!   THE ROOM THE TURN BEGAN IN, in the same step 7 the riposte
#                  runs in and after it. So arriving somewhere is free and
#                  STAYING is not, which is exactly the shape a fight already
#                  has, and on a move the room you LEFT gets its last word
#                  before you go -- the same price `Playthrough::Riposte`
#                  charges for turning your back.
#
# A REFUSED LINE PAYS NOTHING. *"A refused line writes nothing"* is the
# captain's ruling of 2026-09-04 and a toll is something; both callers run this
# only on a line the engine PLAYED, exactly as they run the riposte.
#
# AND A GAME THAT IS OVER PAYS NOTHING EITHER, checked between the two arrival
# branches as well as in front of both: a doorway that took the last hit point
# must not be followed by the room taking another off a corpse, which is
# `Playthrough::Riposte`'s *"the second hound does not get to bite a corpse"*
# read one table over.
#
# THE SAVE IS THE THREE ABILITIES EARNING THEIR KEEP. `Character#check` is the
# kernel -- d20 under the ability, `Character::CHECK_DIE` -- and this class
# builds the generator rather than calling `Playthrough::Turn#check`, because
# that one seeds on the ability's index and two hazards saving on one ability at
# one story moment would then be one die. `Playthrough::Toll.next_sequence`
# gives each toll its own number in its own space; the save and the damage come
# out of that ONE generator in order, which is how `Character::StatBlock` draws
# a whole body.
#
# IT MAKES NO MODEL CALL AND WRITES NO WORLD DATA. `locations.hazard` and
# `location_connections.hazard` are the world's, written by a seed file and by
# nothing else; this reads them.
class Playthrough::Hazards
  attr_reader :playthrough, :turn

  def initialize(playthrough, turn: nil)
    @playthrough = playthrough
    @turn = turn || Playthrough::Turn.new(playthrough)
  end

  # THE COST OF GETTING HERE AND OF BEING HERE, oldest first. `from` is where
  # the party was standing when the turn began, which is what names the one
  # DIRECTED row that was walked; nil for a party that was nowhere, and then
  # only the room's own hazard is paid.
  #
  # Returns the `Playthrough::Toll` rows it wrote -- empty on the ordinary move
  # through the ordinary door into the ordinary room, which is almost every move
  # in every world.
  def on_arrival!(destination, from: nil)
    return [] if destination.nil?

    tolls = []
    tolls << crossing(from, destination)
    tolls << standing(destination, :on_arrival)
    tolls.compact
  end

  # THE COST OF STILL BEING HERE, paid on the room the turn BEGAN in. Same
  # argument and same room as `Playthrough::Riposte#run!`, and called from the
  # same two places straight after it.
  def every_turn!(location:) = [ standing(location, :every_turn) ].compact

  private

  # THE ROOM, WHEN ITS HAZARD IS PAID AT THIS MOMENT. `Location#hazard_at?` is
  # the whole branch: a room with no hazard, or one whose hazard is paid at the
  # other moment, answers false and nothing is rolled.
  def standing(room, moment)
    return nil unless room&.hazard_at?(moment)

    take!(hazard: room.hazard, die: room.hazard_die, save: room.hazard_entry.fetch(:save),
          room: room, connection: nil)
  end

  # THE DOORWAY, AND ONLY THE ONE THAT WAS WALKED. `LocationConnection.walked`
  # reads the single row `origin -> destination`, so a hazard on the other row
  # is not paid and does not have to be excluded: it is one-way by construction.
  def crossing(origin, destination)
    edge = LocationConnection.walked(origin, destination)
    return nil unless edge&.hazardous?

    take!(hazard: edge.hazard, die: edge.hazard_die, save: edge.hazard_entry.fetch(:save),
          room: destination, connection: edge)
  end

  # ONE HAZARD, ROLLED AND WRITTEN DOWN.
  #
  # The save first and the damage second, out of one generator in order. A body
  # that cannot roll the save does not get one: `Character#check` answers nil for
  # somebody with no abilities, and the honest reading of that is that the hazard
  # lands -- a body with no dexterity on record has not dodged anything, and
  # inventing a pass would be inventing the one number `characters.dexterity` is
  # nullable to avoid. `save: nil` in the catalogue is the other way in to the
  # same branch, and it is a decision rather than a gap: there is no ability
  # against having nothing to breathe.
  #
  # Nil for a body with no stat block, which is `#harm!`'s own answer and the
  # same honest nothing: there is no maximum, so there is nothing to take off it.
  def take!(hazard:, die:, save:, room:, connection:)
    who = target
    return nil if who.nil? || playthrough.over?

    sequence = Playthrough::Toll.next_sequence(playthrough)
    rng = Roll.generator(story: playthrough.story_id, playthrough: playthrough.id,
                         at: playthrough.story_now.to_i, sequence: sequence)

    check = save && who.check(save, rng: rng)
    saved = check.present? && check.passed?
    damage = saved ? 0 : Roll.die(die, rng: rng)

    Playthrough::Toll.transaction do
      # NO EARLY RETURN OUT OF THIS BLOCK: since Rails 6.1 a `return` inside a
      # transaction COMMITS it, so a guard written that way would leave a toll
      # behind for a body the engine could not hurt.
      after = turn.harm!(who, damage)
      next nil if after.nil?

      Playthrough::Toll.create!(
        playthrough: playthrough, character: who, location: room, location_connection: connection,
        hazard: hazard, saved: saved, damage: damage, hp_after: after.hp,
        sequence: sequence, story_timestamp: playthrough.story_now
      )
    end
  end

  # WHOSE BODY PAYS IT, and it is the protagonist and nobody else.
  #
  # The same answer `Playthrough::Riposte` gives, and it is here so the two
  # cannot come apart: a hazard that hurt a companion the world's foes would not
  # swing at would be two different answers to "who is the party". Companions
  # standing in the water is a later slice, and `playthrough_tolls.character_id`
  # is a column rather than an assumption so that slice adds no schema.
  def target = playthrough.character
end
