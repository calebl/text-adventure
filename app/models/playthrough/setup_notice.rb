# WHAT THE APP SAYS WHEN THERE IS NO NARRATOR TO ASK.
#
# `Playthrough::TurnFailureNotice` is deliberately vague, because every reason
# a turn fails is internal and none of them are a thing anybody reading the page
# can act on. THESE TWO ARE THE EXCEPTION: no `OPENROUTER_API_KEY` with the
# local rotation off, or a key the provider rejected. Nobody can fix a schema a
# model ignored; anybody running the app can fix these, and until they do the
# only prose the game has is the engine's own factual fallback.
#
# So an unconfigured install SAYS SO, whether or not the turn's own effects were
# committed first -- a taken item and an arrival still stand, and this stands
# above them. Swallowing this into the ordinary fallback made a game with no
# model at all read as a working one whose narrator had merely gone quiet.
#
# The copy is the APP'S, like the other two notices, and names both ways out
# without quoting the provider: `BaseAgent#no_model_message` and
# `#unauthorized_message` carry the exact reason and `NarrationJob` logs them.
module Playthrough::SetupNotice
  # The two failures `BaseAgent` deliberately does not rotate off, because
  # another model cannot fix either of them.
  FAILURES = [ BaseAgent::NoModelConfiguredError, BaseAgent::UnauthorizedProviderError ].freeze

  WAYS_OUT = "Set OPENROUTER_API_KEY for the hosted rotation, or TA_LOCAL_MODELS=1 to use the " \
             "models installed on this machine. The server log names the exact reason.".freeze

  # TWO SENTENCES BECAUSE THERE ARE TWO OUTCOMES, and one of them is not a
  # finished turn. A committed action falls back to the engine's own prose and
  # the turn stands; a call that failed BEFORE any action -- the classifier on
  # an unslashed line is the first one every turn makes -- produced no scene at
  # all, and telling that player the game described their turn would be a
  # sentence about something that did not happen.
  COMPLETED = "No narrator is configured, so the game described that turn in its own plain words. " \
              "#{WAYS_OUT}".freeze
  UNFINISHED = "No narrator is configured, so that turn did not finish. The log and your current " \
               "possessions show what was saved. #{WAYS_OUT}".freeze

  def self.for(error)
    COMPLETED if FAILURES.any? { |kind| error.is_a?(kind) }
  end
end
