# WHAT THE APP SAYS WHEN THE STORY IS OVER, and the one author of it.
#
# `Playthrough::DeathNotice`'s sibling, in the same shape and for the same
# reason -- and the whole of the difference between them is WHY the game ended.
# Death is a body at zero (the captain's ruling of 2026-09-04); this is an arc
# that reached its last step, which writes a `Playthrough::Ending`, a reached
# `Quest::Outcome`, `playthroughs.ended_at` and a closing `Scene`. Both stop the
# game for good; only one of them killed anybody, and the captain's ruling of
# 2026-09-05 on the fight UI is the rule either way: **presentation must say
# what actually happened.** A player who finished their story was told they were
# dead until this file existed.
#
# `Playthrough::EndNotice` is what chooses between the two, off records, and it
# is the only thing that should. Read its header for the rule.
#
# THE THREE THINGS `DeathNotice`'s header says are true here too, and are worth
# saying again rather than pointing at, because a future edit will land in one
# file and not the other:
#
#   NO NARRATION. These are the app's own words, out of the records. The
#   narrator DOES write the last paragraph of a finished story -- that is
#   `Scene::Ending`, and it is a `Scene` in the log above this notice, not this
#   notice. What stands here is the app saying the game is closed.
#   NOTHING IS OFFERED. No epilogue, no new-game-plus, no continue-after-the-end.
#   Every one of those is a mechanic the app does not have.
#   IT SAYS WHAT TO DO NEXT, and it is the same next step death offers: a new
#   playthrough, under the same button, posting to the same place.
#
# THE SECOND PARAGRAPH IS DELIBERATELY THE ONE `DeathNotice` ENDS ON, word for
# word. It is the persistence model stated to the player -- the world keeps
# everything it generated -- and that is true of a finished story exactly as it
# is of a death, so it is said the same way rather than said twice differently.
module Playthrough::StoryOverNotice
  HEADING = "Your story is over.".freeze

  PARAGRAPHS = [
    "This playthrough is finished. Nothing you type will change how it ended, " \
    "and there is no way back into this game.",

    "The world is still there, and it keeps everything it generated. Start a " \
    "new playthrough to walk into it again."
  ].freeze

  # THE ONE-LINE VERSION, for a refused line -- `DeathNotice.sentence`'s shape,
  # and it names the person for that method's reason: a playthrough can be
  # created without a protagonist, and "Odile Vance's story is over" is the fact
  # where "your story is over" is the address.
  def self.sentence(character = nil)
    whose = character&.fullname.presence ? "#{character.fullname}'s story" : "Your story"

    "#{whose} is over, and this playthrough with it. Nothing you type can change how it ended. " \
      "Start a new playthrough to play this world again."
  end
end
