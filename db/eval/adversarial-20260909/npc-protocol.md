# NPC agency evaluation protocol — 2026-09-09

This protocol is fixed before reading any live response. The unchanged five
fictional cases in `npc-agency-eval.rb` run four times per side. The before is
stored and reviewed in full before the frozen candidate is run. Each case is a
fresh, rolled-back game with an explicitly snapshotted NPC inventory. There are
no real player conversations or personal records in the corpus.

## Arm and spending

Both sides use only OpenRouter `mistralai/mistral-medium-3.1`, through BaseAgent,
with provider fallback disabled, SDK retries disabled, and at most 2,048 output
tokens per request. NPC and arrival evaluations share the same locked $3 ledger
at `/tmp/text-adventure-live-eval-20260909/budget.json`. The local guard reserves
at conservative bounds of $5/M input and $20/M output tokens, checks seeded model
pricing before requests, and settles each reservation using returned provider
cost or conservative token accounting. Unknown charges retain the reservation.
The root agent verified the public OpenRouter rate as $0.40/M input and $2/M
output before execution. Actual model, token usage, costs, prompts, and responses
are retained for audit. A guard/configuration failure stops work for inspection.

## Scoring fixed before responses

The primary metric is the fraction of these five cases whose resulting state
does not match the requested outcome. It is computed separately for each of the
four complete repetitions, then compared using the existing `Eval::Noise` exact
rank test (four before observations and four after observations).

| Case | Required recorded state |
| --- | --- |
| give-owned-key | Player carries the brass key; NPC does not follow and is not a foe. |
| follow-through-door | NPC following is true; player has no key and NPC is not a foe. |
| honor-ceasefire | NPC is no longer a foe; player has no key and NPC does not follow. |
| refuse-trusted-key | Player has no key; NPC does not follow and is not a foe. |
| cannot-give-absent-item | Player has no key; NPC does not follow and is not a foe. |

These fixtures test a conversation's immediate effect. Following across a real
move and ending a fight are covered by deterministic engine tests and sweeps;
the live fixture alone does not establish those later behaviors. A refusal can
pass on the before even without an action channel. An error does not erase an
otherwise correct state result; failures are measured separately.

Secondary metrics, each reported per repetition and compared by `Eval::Noise`:

- Exchange failure fraction: a row has an error, or any paid call receipt has an
  error. This includes a rendering failure recovered by factual engine prose.
- State contradiction fraction: manually inspect every displayed narration for
  a definite claim inconsistent with the recorded resulting state. An explicit
  completed handover, established accompaniment, or cessation of fighting counts
  if the relevant state remains false. A bare intention, conditional offer,
  future promise, metaphor, or private reaction does not count as a completed
  action. A narrated surrender of the entrusted key or an invented silver crown
  counts. Empty narration is recorded as failure, not a contradiction. Each
  positive judgment must retain a short excerpt and a reason.
- Reaction word count: total Unicode word tokens across the six original
  reaction fields, excluding the added engine action field; take the mean over
  the five cases in each repetition.
- Narration word count: Unicode word tokens in displayed narration, averaged
  over the five cases in each repetition. A word is a run of Unicode letters or
  numbers optionally joined by apostrophes or hyphens. Missing text has zero.

Word counts measure length, not realism or quality. The primary claim concerns
engine state, not a broad claim that characters now simulate rich independent
lives. All cases are included, including failures. No case/scorer substitution,
best-of selection, or post-result threshold changes are permitted. Action choice
and applied/rejected receipt fields are retained as explanatory diagnostics;
the old implementation lacks them, so they are not required to pass an old case.

The exact rank-test verdict may be real, noise, or inconclusive. A reduction in
state failures or contradictions is favorable. Length deltas have no presumed
favorable direction. Four repetitions are the minimum gate, not evidence of
broad model generalization.
