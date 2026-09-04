# WHAT THE APP SAYS WHEN THE PLAYER IS DEAD, and the one author of it.
#
# THE CAPTAIN'S RULING, 2026-09-04, in his words: *"zero hit points means death.
# Playthrough is over and you can't do anything else. You have to start a new
# playthrough. Eventually, we can add going back to saved previous state."*
#
# So death here is not a condition and not a scene. It is the END OF THE GAME,
# and everything below follows from that:
#
#   NO NARRATION. The engine says it, in the app's own words, out of the records
#   -- the same rule `Playthrough::Refusal` is under. Asking a narrator to write
#   a death is asking a model to say something about a state the engine owns,
#   and it would cost a call on a turn that does nothing.
#   NOTHING IS OFFERED. No death save, no unconscious state, no scar, no
#   revival, no restore-from-save. Every one of those is a mechanic the captain
#   deferred, and copy that hinted at one would be promising a thing the app
#   does not have.
#   IT SAYS WHAT TO DO NEXT. A terminal state with no way out is a dead page.
#   The one true next step is a new playthrough, so that is what it says and
#   what the play page puts a button under.
#
# TWO SHAPES, ONE SET OF WORDS. `#sentence` is what a refused line is answered
# with -- the player typed something and the engine will not play it -- and
# `HEADING` / `PARAGRAPHS` are the standing statement the play page shows where
# the input used to be. They are here together so the two cannot come to
# disagree about whether the game is over.
module Playthrough::DeathNotice
  HEADING = "You are dead.".freeze

  PARAGRAPHS = [
    "This playthrough is over. Nothing you type will change what happened, and " \
    "there is no way back into this game.",

    "The world is still there, and it keeps everything it generated. Start a " \
    "new playthrough to walk into it again."
  ].freeze

  # THE ONE-LINE VERSION, for a refused line. It names the person when the
  # records have one -- a playthrough can be created without a protagonist, and
  # "Odile Vance is dead" is the fact where "you are dead" is the address.
  def self.sentence(character = nil)
    who = character&.fullname.presence || "You"
    verb = character ? "is" : "are"

    "#{who} #{verb} dead, and this playthrough is over. Nothing you type can change it. " \
      "Start a new playthrough to play this world again."
  end
end
