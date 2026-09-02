# WHAT THE APP SAYS WHEN IT WILL NOT LET A CHARACTER ANSWER.
#
# A model asked to play a person sometimes stops playing them and hands the
# player a real-world crisis line instead -- measured twice in 207 responses
# (`data/ta-refusal-range/report.md`), both times inside an NPC's dialogue, in
# a gaslight world whose only telephone is a telegraph the Houses own. The app
# had two bad options and one good one:
#
#   ROUTE AROUND IT   rotate to another model in the list, which narrates the same
#                     exchange in fiction with no intervention. Consistent with
#                     "the world reacts by its own rules", and the game never
#                     shows anything.
#   LET IT THROUGH    keep the model's version. Preserves the safety behaviour
#                     and costs a broken world, an anachronism in the turn log,
#                     and a `Scene` row signed "-MiniMax" in a world that keeps
#                     what it generates.
#   INTERCEPT         suppress the model's version entirely and say something
#                     the app wrote, outside the fiction.
#
# The third is what was chosen, and this is the something. `BaseAgent` raises
# `CrisisResponseError` without rotating, so the model's text never becomes a
# `Scene` and is rolled back out of the stored conversation too; `NarrationJob`
# shows this in its place.
#
# WHY IT IS WRITTEN THE WAY IT IS. It may be read by a person in real distress,
# and it is the app talking rather than a character, so:
#
#   * It says so in the first line. A message about suicide arriving in the
#     narrator's voice would be the same failure the interception exists to
#     stop, one layer up.
#   * IT NAMES NO PHONE NUMBER. The player's country is not known -- there is no
#     location on a `Playthrough` and no reason to add one for this -- and a
#     crisis number that is wrong for where somebody is standing is worse than
#     no number at all. It says how to find the right one instead, and it says
#     why it is not guessing.
#   * It is not clinical and it diagnoses nothing. It does not tell the player
#     what they are feeling, and it does not treat the command they typed as
#     evidence about them: a grim game invites grim commands, and the trigger
#     here was the MODEL's answer, not the player's input.
#   * It does not end the playthrough or take the input away. The turn simply
#     produced no scene, and the story is where they left it.
#
# Changing this text is changing something a distressed person reads. Read the
# four rules above first.
module Playthrough::SafetyNotice
  HEADING = "This is the game speaking, not a character.".freeze

  PARAGRAPHS = [
    "That turn went somewhere we would rather not have a character answer, so " \
    "we have stepped outside the story for a moment. Nothing you typed was " \
    "wrong, and nothing was lost.",

    "If any of it is close to home, please talk to someone — someone you " \
    "trust, or a crisis line. Almost every country has a free one. We have " \
    "not printed a number here because we do not know where you are, and a " \
    "wrong number is worse than none; a search for \"crisis line\" and the " \
    "name of your country will find the right one.",

    "The story is where you left it, whenever you want to go back to it."
  ].freeze
end
