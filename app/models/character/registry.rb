# WHERE A PERSON ENDS UP, and the one thing in the app that decides it without
# being told to. The people half of the noun registry: `Item::Registry` says
# how a thing comes to be lying in a room, this says how a person comes to be
# standing in one.
#
# THE ONE RULE IT EXISTS FOR: A CHARACTER WHO ALREADY HAS A WHEREABOUTS IS NOT
# MOVED. That is the Tide Post defect written down. `Scene::Generator` used to
# work out the room's cast from scratch on every arrival -- the protagonist,
# anyone `is_companion`, and whoever was in the last scene here that recorded
# anybody -- so a place nobody had visited was empty, and arriving at The Tide
# Post recorded the protagonist alone on all three runs checked, in a world
# whose whole premise is Neb Halloran chained to that post. A cast that is
# regenerated is a cast that forgets. So a proposed cast is a PROPOSAL: this
# reconciles it against the records, the records win wherever they have an
# answer, and the arrival Scene's cast is then written FROM the records.
#
# WHAT IT REFUSES, and each is a real candidate:
#
#   somebody already somewhere else  left exactly where they are. The proposal
#                                    is evidence about a room, never authority
#                                    over a person.
#   a room already at its cap        `MAX_PER_ROOM`, read back from the records
#                                    on every admission the way both of
#                                    `Item::Registry`'s caps are.
#   a name nothing answers to        refused, because THIS CLASS DOES NOT
#                                    CREATE PEOPLE. See below.
#
# IT PLACES AND IT DOES NOT INVENT, which is the line between this task and
# `ta-narrator-memory`. An `Item` is a name and one line -- ~15 output tokens
# riding on a call the room is already paying for -- which is why
# `Item::Registry` can create one outright. A `Character` is nine validated
# fields and a whole model call of its own (`Character::Generator`), so putting
# people into `Location::DetailSchema` would add a round trip's worth of output
# to the most expensive thing a move does, on every room, and would change what
# every generated world contains with no measurement to judge it by. That is a
# world-population feature and it is queued as one: the ROADMAP assigns the
# stub-then-realize character shape to `ta-narrator-memory`. **This is the seam
# it plugs into** -- `#admit!` already takes names, already refuses an unknown
# one with the reason, and creation is the one branch that has to change.
#
# Refusals are DROPPED, never raised, on `Item::Registry`'s rule: a room
# realized with two of the three people the proposal named is a good room, and
# a realization that threw away its description over a cast is not.
#
# WHAT CALLS `#admit!` TODAY: nothing in `app/`, and that is stated rather than
# hidden. Nothing in the app produces a proposed cast yet -- the seed file
# writes its own placements straight, because a hand-authored world IS the
# decision and re-seeding has to be able to put a played world's cast back
# (`WorldSeed::Loader#load_characters!`), and `Character#move_to!` is the
# explicit call for a mechanic that means to move somebody. So this is a seam
# with its rule written down and tested, in the same way
# `EngineSweep::Invariants#doors_unchanged` asserts something an offline walk
# cannot currently break: it is the assertion the DEFECT broke, and it fires
# the moment anything starts proposing a cast. `MAX_PER_ROOM` is not idle
# either -- `Story::Doctor` reports a room past it, exactly as it reports a
# room past `Item::Registry::MAX_PER_ROOM`.
class Character::Registry
  # HOW MANY PEOPLE THE ENGINE WILL PLACE IN ONE ROOM, in total and not per
  # call -- the same distinction `Item::Registry::MAX_PER_ROOM` documents. It
  # bounds PLACEMENT and nothing else: a seed file may hand-author a crowd (it
  # is world data, written by a person, and `WorldSeed::Loader` places exactly
  # what the file says), and `#move_to!` is an explicit decision. What this
  # stops is a room quietly accumulating a cast nobody chose.
  #
  # Three, and it is the same number for the same reason `Item::Registry` picks
  # three: `Playthrough::Classifier` offers the room's cast as a closed enum on
  # every single turn, and the fullname AND nickname of everybody present go
  # into it. Three people is six names, which is a list a player can hold in
  # their head and a model can copy from exactly.
  MAX_PER_ROOM = 3

  attr_reader :location, :story

  def initialize(location)
    @location = location
    @story = location.story
  end

  # Turns a proposed cast into placements and returns WHO IS ACTUALLY HERE
  # afterwards, read back out of the records.
  #
  # `candidates` may hold `Character` records or the names of them, because the
  # two things that propose a cast do it differently: a seed file names people
  # in a `location:` and a future generator will name them in a schema'd answer.
  # Anything that does not resolve to somebody in this story is refused with a
  # reason in the log.
  def admit!(candidates)
    Character.transaction do
      Array(candidates).each { |candidate| admit_one(candidate) }
    end

    present
  end

  # WHO THE RECORDS PLACE HERE. The closed set, read through the one scope, so
  # a caller of this class never has to know how presence is stored.
  def present
    Character.present_in(location).to_a
  end

  # HOW MANY MORE PEOPLE MAY BE PLACED HERE, read from the records on every
  # check rather than counted once -- rows are written as the loop goes, and a
  # budget worked out before it would not notice. `Item::Registry#room_for_items`
  # has the same shape and the same reason.
  def room_for_people
    [ MAX_PER_ROOM - Character.present_in(location).count, 0 ].max
  end

  private

  def admit_one(candidate)
    character = resolve(candidate)
    return refuse(label(candidate), "this story has nobody of that name, and placing people is not inventing them") if character.nil?

    reason = refusal(character)
    return refuse(character.fullname, reason) if reason

    character.update!(location: location)
  end

  # The one place that says no, and it says which no. The whereabouts check is
  # first because it is the rule this class exists for: a room at its cap that
  # names somebody already standing somewhere else should read as "he is at the
  # post", not as "the room is full".
  def refusal(character)
    if character.somewhere?
      return nil if character.location_id == location.id

      return "#{character.pronoun_forms.subject} is already in #{character.location.name}, and a proposal does not move anybody"
    end

    return "the room already holds #{MAX_PER_ROOM}" if room_for_people.zero?

    nil
  end

  # A `Character` of this story, however it was named. Matched on fullname or
  # nickname, case-insensitively, which is the pair `Playthrough::Classifier`
  # already offers a player -- a proposal should be able to say "Neb" for the
  # same reason a player can.
  def resolve(candidate)
    return candidate if candidate.is_a?(Character) && candidate.story_id == story.id

    name = candidate.is_a?(Character) ? candidate.fullname : candidate.to_s
    return nil if name.blank?

    story.characters.where("LOWER(fullname) = ? OR LOWER(nickname) = ?", name.downcase, name.downcase).first
  end

  def label(candidate)
    candidate.is_a?(Character) ? candidate.fullname : candidate.to_s
  end

  def refuse(name, reason)
    Rails.logger.info do
      "[cast] #{location.name.inspect} did not take #{name.presence.inspect || "an unnamed person"}: #{reason}"
    end
    nil
  end
end
