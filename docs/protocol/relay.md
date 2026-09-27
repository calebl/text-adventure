# The model relay

An engine running on a player's own machine needs a model. It has two ways to
one: the player's own OpenRouter key, which goes straight to OpenRouter and
never reaches this server, or this relay, which answers with the instance
owner's key for an invited player, under that player's monthly limit.

The relay's paths are OpenRouter's paths under another base URL, so an engine
sends the same request bodies either way. Only the base URL and the bearer
token change.

| Route | Base URL | Bearer |
| --- | --- | --- |
| Direct | `https://openrouter.ai` | the player's OpenRouter key |
| Relay | `https://<instance>/relay/openrouter` | the player's token (the same one `/api/v1` takes) |

## Endpoints

| Request | Forwarded to |
| --- | --- |
| `POST /relay/openrouter/api/v1/chat/completions` | `https://openrouter.ai/api/v1/chat/completions`. With `"stream": true` the answer is passed through as Server-Sent Events, chunk by chunk. |
| `POST /relay/openrouter/api/alpha/decisions` | `https://openrouter.ai/api/alpha/decisions` |

Nothing else is served under `/relay`.

## Authentication

`Authorization: Bearer <token>`, exactly as for [`/api/v1`](v1.md#authentication):
the operator invites a player, and a revoked token stops working. A missing,
wrong or revoked token gets `401`.

## What is forwarded

Only the request body, and only when it passes these checks. No header the
client sent is forwarded.

- **The model** must be one the engine itself uses: on the chat route, one of
  `BaseAgent::REMOTE_MODEL_IDS`; on the decisions route, the pinned Jev
  (`SystemOneAgent::OPENROUTER_MODEL`).
- **The fields** must be in `Relay::Request::FIELDS` for the route. Any other
  top-level field is refused by name, not dropped.
- **`max_tokens`** is at most `Relay::Request::MAX_OUTPUT_TOKENS`. A chat that
  sets none is sent with that ceiling. A stream is always sent with
  `stream_options.include_usage`, so its last event carries its usage.
- **The body** is at most `Relay::Request::MAX_BYTES` for the route.

## Spend

The relay shares the player's monthly limit with the hosted engine: see
[Spend](v1.md#spend). Before a call is forwarded, the relay holds a reservation
for it: the call's worst case, priced from its size and its output ceiling. The
call is forwarded only if the month's spend, plus everything already held,
plus this reservation, stays within the limit. When the call ends, the hold is
replaced by what the call cost, read from OpenRouter's usage on the response
(for a stream, from its last event). A call whose cost is unknown, such as a
stream cut off before its usage arrived, is charged its whole reservation.

## Errors

Errors have OpenRouter's shape, so a client reads a relay refusal the way it
reads an OpenRouter one:

```json
{"error": {"code": 402, "message": "…", "metadata": {"reason": "limit_reached"}}}
```

| status | `metadata.reason` | meaning |
| --- | --- | --- |
| 400 | `invalid_request` | the body is not JSON, names a model or field the relay does not forward, or sets `max_tokens` past the ceiling |
| 401 | `unauthorized` | no valid token |
| 402 | `limit_reached` | this month's limit is reached; nothing was sent. The message says how to add your own OpenRouter key |
| 413 | `invalid_request` | the body is past the size ceiling |
| 429 | `rate_limited` | more than `Relay::OpenrouterController::CALLS_PER_MINUTE` calls in a minute |
| 502 | `upstream_unavailable` | no model could be reached |
| 503 | `not_configured` | this instance does not relay |

Any other error from OpenRouter is passed on as OpenRouter sent it.

## Privacy

Every relayed request passes through the instance on its way to OpenRouter and
the model provider. The relay does not log request or response bodies. It keeps
one receipt per call: the player, the model, the token counts and the cost.
