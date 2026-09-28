# WHAT THE APP SAYS WHEN A GAME IS OVER AND THE RECORDS DO NOT SAY WHY, and the
# one author of it.
#
# The third sibling of `Playthrough::DeathNotice` and
# `Playthrough::StoryOverNotice`, in the same shape. `playthroughs.ended_at` is
# set, there is no `Playthrough::Ending`, and the protagonist is not at zero --
# or there is no protagonist to be at zero. `Playthrough::EndNotice` is what
# picks it, off records, and its header lists what leaves such a row.
#
# IT CLAIMS NOTHING THE RECORDS DO NOT HOLD. Not a death, because nobody is at
# zero; not an ending, because none was reached. What IS on record is that the
# game stopped and that the story did not reach an ending, so that is all it
# says. The owner's ruling on it replaced the death copy this case used to be
# shown: **presentation must say what actually happened**, and "you are dead"
# over a living protagonist is not what happened.
#
# THE THREE THINGS the other two headers say are true here too:
#
#   NO NARRATION. The app's own words, out of the records.
#   NOTHING IS OFFERED. No resume, no repair from the play page -- a game
#   stopped this way is `Story::Doctor`'s finding, for the person who can read
#   the database, and not the player's problem to solve.
#   IT SAYS WHAT TO DO NEXT: a new playthrough, under the same button.
#
# THE SECOND PARAGRAPH IS THE ONE BOTH SIBLINGS END ON, word for word, for the
# reason `StoryOverNotice`'s header gives: the world keeps everything it
# generated however the game stopped.
module Playthrough::StoppedNotice
  HEADING = "Your story has stopped.".freeze

  PARAGRAPHS = [
    "This playthrough stopped before the story reached an ending. Nothing you " \
    "type will change that, and there is no way back into this game.",

    "The world is still there, and it keeps everything it generated. Start a " \
    "new playthrough to walk into it again."
  ].freeze

  # THE ONE-LINE VERSION, for a refused line -- the siblings' shape, naming the
  # person when the records have one.
  def self.sentence(character = nil)
    whose = character&.fullname.presence ? "#{character.fullname}'s story" : "Your story"

    "#{whose} stopped before it reached an ending, and this playthrough with it. " \
      "Nothing you type can change it. Start a new playthrough to play this world again."
  end
end
