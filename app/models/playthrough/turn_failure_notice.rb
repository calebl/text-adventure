# WHAT THE APP SAYS WHEN A TURN DID NOT FINISH.
#
# `NarrationJob`'s general rescue used to hand the player `e.message`, so the
# `.alert` above the log read, verbatim:
#
#   generated text arrived at its 320-character cap (320 characters), so it was
#   cut off rather than finished: "…the desk across from his own workspace,."
#
# Which is a good log line and a terrible thing to show somebody who typed
# "ask him about the ledger". It names an internal cap, quotes a fragment of a
# model's answer the app decided not to keep, and tells the player nothing they
# can act on -- and on the measured talk path (`data/ta-conversation-read/report.md`
# §4) it was what most turns produced.
#
# So the message is the app's, written once, like `Playthrough::SafetyNotice`:
# a turn failed, nothing was lost, try again. It is deliberately vague about
# WHY, because every reason is an internal one -- a model that would not answer,
# a schema it ignored, a sheet it cut in half -- and none of them are a thing
# the player did or can fix. `Rails.logger.error` keeps the real error in full,
# which is where a reason belongs.
#
# NOT a `SafetyNotice`, and the two must not converge: that one is an
# interception the app chose, shown at the foot of the log in the app's voice
# because nothing went wrong. This one is a failure, and it is styled as one.
module Playthrough::TurnFailureNotice
  MESSAGE = "Something went wrong on our side and that turn did not finish. " \
            "Nothing was lost — the story is exactly where you left it. " \
            "Try again, or try saying it another way.".freeze
end
