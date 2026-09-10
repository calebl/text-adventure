# NPC agency: four repetitions per side

The prepared candidate fixes all twelve missing positive state effects in these
fixtures while preserving eight appropriate refusals. The before narrated
agreements and gifts without changing the game; the candidate records item
ownership, following, and ceasefire through validated engine actions.

The [protocol](npc-protocol.md) was written before live responses were read.
Each repetition includes the same five fresh fictional cases, and the full
baseline was stored and reviewed before candidate execution. Both sides used
only `mistralai/mistral-medium-3.1` through OpenRouter, with provider fallback and
SDK retries disabled. Raw [before](npc-before.json) and [after](npc-after.json)
include every prompt, response, actual model, token receipt, and engine result.

| Metric | Before | After | Existing exact rank-test verdict |
| --- | --- | --- | --- |
| State failures | 12/20; every repetition 60% | 0/20; every repetition 0% | Real, p=0.028571 |
| Displayed-prose state contradictions | 6/20; repetitions 40%, 40%, 20%, 20% | 0/20 | Real, p=0.028571 |
| Exchange or paid-call errors | 0/20 | 0/20 | Noise, p=1 |
| Median per-repetition reaction words | 56.8 | 55.6 | Noise, p=0.457143 |
| Median per-repetition narration words | 36.2 | 35.7 | Noise, p=0.885714 |

There are four statistical observations per side, each aggregating all five
cases. The [comparison](npc-comparison.json) contains the unrounded samples and
`Eval::Noise` results. The [manual audit](npc-contradiction-audit.json) records a
judgment for every displayed passage. Its strict rubric excludes mere offers or
future promises: two before gifts describe completed transfers and four before
truces explicitly end fighting while the NPC remains a foe. The missing
following flag still fails the primary state metric even when its prose only
says the NPC is ready to go.

All four candidate key gifts applied the engine-selected owned item. All four
following requests set following. All four ceasefires removed the NPC from foes.
The entrusted-key and absent-crown cases chose `none` in every repetition. No
candidate action was rejected and no candidate fallback prose was needed.

These cases establish this bounded conversation-to-state path. They do not
establish long-term autonomous planning, realistic psychology, or safe execution
of arbitrary free-text actions. Movement with followers, staying behind,
renewed fighting after a truce, item isolation, and recovery are additionally
covered by deterministic model tests and engine sweeps. Prose can still omit an
applied effect: one successful gift describes offering the key without clearly
completing the handover. Engine state remains authoritative.

The clean baseline made 40 calls using 24,619 input and 3,318 output tokens; its
registry-priced total is $0.01649428. The candidate made 40 calls using 27,297
input and 3,420 output tokens; its registry-priced total is $0.01779788. Direct
provider costs are present for the 20 structured calls on each side, totaling
$0.00997716 and $0.01078004 respectively. Streaming narration exposes usage but
no raw provider billing amount, so those calls retain conservative usage-based
accounting in the shared ledger. Registry-priced totals are usage estimates,
not a claim to have received a bill for every streamed call.

An initial 40-call baseline attempt encountered a bug in evaluation cost capture:
it tried to parse an empty streamed response body as JSON. That whole
[instrumentation-failure batch](npc-before-instrumentation-failure.json) is
preserved, excluded from model comparison, and remains charged to the same
budget ledger. No unknown reservation was refunded. The unchanged corpus was
rerun after fixing the instrumentation. The
[instrumentation manifest](npc-instrumentation-manifest.json) records original,
streaming-fixed, and final defensive helper hashes, including the tiny helper
version difference between the clean arms. No prompt or case changed between
those helper versions. Final helper offline checks pass five tests with 39
assertions; the evaluator, scorer, helper, and helper tests pass RuboCop.
Across all 120 NPC requests, including the failed attempt, the guard accounts
for $1.659355; $1.467620 of that is deliberately retained unknown reservations.
This is a conservative budget figure, not reported actual provider spending.

The held production integration was not applied by this evaluation. Its bounded
agency claim has now passed the required stored-baseline/four-run comparison
gate; final integration and full repository checks remain with the root agent.
