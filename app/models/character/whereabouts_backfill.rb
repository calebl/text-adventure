# WHERE SOMEBODY WAS, RECOVERED FROM THE ONLY RECORD THAT EVER HELD IT.
#
# `characters.location_id` is written from now on -- by the seed file, by
# `Character::Registry`, by `Character#move_to!`. Every character in a database
# older than the column has none, so `Character.present_in` answers nobody and
# a world somebody has already played becomes a world with nobody in it. The
# answer is still on disk, in the one place presence was ever recorded: the
# cast of an arrival `Scene`. `rake game:backfill_whereabouts` runs this.
#
# THREE OUTCOMES, TOLD APART, and the third is the reason this is careful:
#
#   placed        every scene that recorded this person, at the latest story
#                 moment any of them did, is in the same room. That room is
#                 where they were.
#   ambiguous     two rooms recorded them at the same moment, or the scenes
#                 that recorded them carry no story time at all so there is no
#                 order to choose from. NOTHING IS WRITTEN and they are
#                 reported: a person cannot be in two rooms, so a backfill that
#                 picked one would be inventing which.
#   unrecoverable no scene ever recorded them. Nothing is written. Nowhere is
#                 the honest answer and `rake game:doctor` says so.
#
# IT REFUSES TO GUESS, which is `Scene::TransitionBackfill`'s rule and the same
# argument: a blank column says "not known" and a wrong one says something
# false. Presence is worse than a transition here -- the cast is the closed set
# `talk` resolves against, so a person put in the wrong room is somebody the
# player can speak to who is not there.
#
# SOMEBODY ABSENT ON PURPOSE IS SKIPPED TOO. `characters.deliberately_absent`
# is the file saying nowhere is the story (`The Unrecorded Hour` about Perrin
# Lasco), so an old arrival cast that names them is evidence this must not act
# on: it would undo a premise and write a row that says both things at once.
#
# THE PROTAGONIST AND COMPANIONS ARE SKIPPED, because their whereabouts is not
# this column: the party is wherever the playthrough is
# (`playthroughs.current_location_id`), and two people playing one world stand
# in two rooms at once. Every old arrival cast names the protagonist, so
# backfilling from it would write one player's position onto the story.
#
# Offline, deterministic, free: no model call, no network.
class Character::WhereaboutsBackfill
  # ONE CHARACTER'S ANSWER, and why it is that. `rooms` is what the scenes said
  # at the winning moment -- one name when it is decided, several when it is
  # not -- so the report can print the disagreement rather than just naming it.
  Answer = Data.define(:character, :outcome, :location, :rooms) do
    def initialize(location: nil, rooms: [], **rest) = super

    def placed? = outcome == :placed
    def ambiguous? = outcome == :ambiguous
  end

  attr_reader :story

  def initialize(story)
    @story = story
  end

  # Returns the `Answer`s, in cast order, for the characters that had no
  # whereabouts when it started. Somebody already placed is not touched at all:
  # this is a backfill, not a re-derivation, and the records win over the
  # history everywhere else in this app.
  def run(dry_run: false)
    candidates.map do |character|
      answer = answer_for(character)
      character.update!(location: answer.location) if answer.placed? && !dry_run
      answer
    end
  end

  # Everybody this could speak for: nowhere, and not the party.
  #
  # NOWHERE ON PURPOSE IS NOT A GAP. `characters.deliberately_absent` is a
  # world's own statement that this person has been removed from it, and an old
  # arrival cast that happens to name them is exactly the evidence that must
  # not win -- `Character::Registry` refuses to place them for the same reason.
  # Recovering a room for them would undo a premise, and it would write a row
  # that says both things at once.
  def candidates
    story.characters.nowhere.where(deliberately_absent: false).where(is_protagonist: false)
         .where(is_companion: [ false, nil ]).order(:id).to_a
  end

  private

  # THE LATEST MOMENT ANY SCENE PUT THEM SOMEWHERE, and every room that claimed
  # them at it. One room is an answer; two is a disagreement with no tie-break,
  # which is refused.
  #
  # A scene with no `story_timestamp` is invisible to the story's own clock
  # (`Story#clock`), so it cannot be ordered against one that has it. Those are
  # gathered separately: if they all name one room, and it is the same room the
  # timed ones name -- or there are no timed ones -- the answer is still
  # decided. Otherwise there is no order to choose from and it is ambiguous.
  def answer_for(character)
    scenes = character.scenes.includes(:location).to_a
    return Answer.new(character: character, outcome: :unrecoverable) if scenes.empty?

    timed = scenes.select(&:story_timestamp)
    rooms = timed.any? ? rooms_at_the_last_moment(timed) : room_names(scenes)
    rooms |= room_names(scenes.reject(&:story_timestamp)) if timed.any? && timed.size < scenes.size

    return Answer.new(character: character, outcome: :ambiguous, rooms: rooms.sort) unless rooms.one?

    Answer.new(character: character, outcome: :placed, rooms: rooms,
               location: story.locations.find_by(name: rooms.first))
  end

  def rooms_at_the_last_moment(timed)
    latest = timed.map(&:story_timestamp).max

    room_names(timed.select { |scene| scene.story_timestamp == latest })
  end

  def room_names(scenes)
    scenes.filter_map { |scene| scene.location&.name }.uniq
  end
end
