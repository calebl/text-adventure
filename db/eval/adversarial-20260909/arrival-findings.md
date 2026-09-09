# Arrival evaluation findings

Four repetitions per side over three fixed fictional cases, using the same pinned OpenRouter model. Both arms completed all twelve calls without model errors. All emitted inputs and responses are stored beside this report.

The candidate fixed the living-dead-character contradiction in every tested arrival. The broader contradiction count fell from seven of twelve descriptions to one of twelve, but the predeclared exact rank test is INCONCLUSIVE (p = 0.057143). This is a promising observed difference, not a proven general prose improvement.

| Reading (lower is better unless noted) | Before median rate | After median rate | Verdict | Exact p |
| --- | ---: | ---: | --- | ---: |
| description_contradiction | 0.667 | 0.000 | INCONCLUSIVE | 0.057143 |
| description_fact_missing_strict | 1.000 | 0.667 | NOISE | 0.142857 |
| description_fact_missing_inclusive | 1.000 | 0.333 | REAL | 0.028571 |
| summary_fact_missing_strict | 1.000 | 0.333 | REAL | 0.028571 |
| failed_call | 0.000 | 0.000 | NOISE | 1.000000 |
| description_words | 77.000 | 71.167 | NOISE | 0.085714 |
| seconds | 1.756 | 1.796 | NOISE | 1.000000 |

The primary contradiction labels agreed between two readers. Three corpse descriptions suggested death without stating it, so strict and inclusive acknowledgment are both retained. Strict acknowledgment did not establish improvement; inclusive body interpretation did. No selection between those readings is presented as the single winning score.

## What still failed

- One candidate arrival explicitly put the already-carried brass key back on the desk. The engine inventory remained correct.
- None of the eight crossing descriptions, before or after, clearly acknowledged injury or pain. All four candidate summaries recorded the HP loss, but summaries are internal context rather than the prose displayed to the player.
- A candidate corpse description put fingers around a key that the records placed in the room. This secondary placement discrepancy is retained in the annotations; it was not retrofitted into the primary score.

## Resulting implementation decision

Integrate the corrected per-game destination context and living-cast gate; retain the observed prose limits. Show each claimed crossing outcome directly from its persisted toll record beneath the prose. This notice is a deterministic app result, separately tested through the actual view and engine sweep. It is not appended to Scene.description and is not counted as improved model output. The prompt tested here remains unchanged.

The blinded packets, both independent annotation files, their identity key and compare_arrival.rb permit an offline re-read and re-score. The original and candidate responses are retained; no prior baseline is replaced.
