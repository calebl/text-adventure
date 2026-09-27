# THE MODEL RELAY: OpenRouter's two routes, mirrored under /relay/openrouter,
# answered with the owner's key for an invited player and under that player's
# one monthly cap.
#
# A player who runs the engine on their own machine needs a model, and has two
# ways to one: their own OpenRouter key, which goes straight to OpenRouter and
# never comes here, or this relay. The relay's paths are OpenRouter's paths
# under a different base, so the engine sends the same request bodies either
# way and only the base URL and the bearer differ:
#
#   POST /relay/openrouter/api/v1/chat/completions   (a stream is passed through)
#   POST /relay/openrouter/api/alpha/decisions
#
# WHO MAY USE IT is exactly who may use /api/v1: a `Player`, by the same bearer
# token, compared the same way, and revoked the same way. WHAT THEY MAY SPEND is
# the same allowance too -- every forwarded call leaves a `RelayReceipt`, which
# `Player::Allowance#spent` sums beside the hosted engine's own receipts, so a
# player has one monthly cap whichever way they play.
#
# WHAT IS FORWARDED is decided here and in `Relay::Request`, never by the
# player: an allowlisted model, a closed set of body fields, a ceiling on
# `max_tokens` and a ceiling on the request's size. Nothing else crosses --
# no header the player sent, no field the table does not name.
#
# THE OWNER'S KEY is `RELAY_OPENROUTER_API_KEY`, deliberately not the everyday
# `OPENROUTER_API_KEY`: an instance can play with one and relay with the
# other, and a machine with only the everyday key has no relay at all. The key
# is read when a request is sent and nowhere else. It is never logged, never
# put in a receipt, never echoed in a response or an error; a response that
# somehow carried it has it struck out (`.redact`).
#
# THE RELAY MAKES NO MODEL CALL OF ITS OWN. It forwards a request another
# engine built, so `BaseAgent` and `SystemOneAgent` -- the ways this app calls a
# model -- are not in its path; `Relay::Upstream` is the one place a forwarded
# request leaves, and it speaks to OpenRouter only.
#
# NO PROMPT BODY IS KEPT. Rails would log a JSON body as parameters, and on a
# body that does not parse it would log the body whole; the controller shuts
# both off (`Relay::OpenrouterController#dispatch`). What is kept of a call is
# its receipt's numbers.
module Relay
  KEY_VARIABLE = "RELAY_OPENROUTER_API_KEY".freeze

  UPSTREAM = URI("https://openrouter.ai").freeze

  # Whether this instance can relay at all. Without the key the routes answer
  # 503 and nothing is reserved or recorded.
  def self.configured? = ENV[KEY_VARIABLE].present?

  # Any occurrence of the owner's key in text on its way out, struck out.
  # Nothing upstream is expected to echo it; this is so that nothing can.
  def self.redact(text)
    key = ENV[KEY_VARIABLE]
    return text if key.blank? || text.blank?

    text.gsub(key, "[REDACTED]")
  end
end
