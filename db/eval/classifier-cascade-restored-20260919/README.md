# The cascade, on the request wording the arm was actually scored on

The **after** side of the request-wording restoration, and the reason the pair
exists: the shipped `also_named` and per-action target sentences were an earlier
revision of the arm the design of record was chosen on, and restoring them is a
prompt change, so it needed a baseline either side of it.
`classifier-cascade-before-20260919` is that baseline.

Same arm (`mistralai/mistral-medium-3.1` as the escalation target), same 343
lines at corpus digest `a259e93e6b865af1`, same scorer, same eight calls in
flight, four repetitions. The only thing that moved is those eight instruction
strings.

## Before and after

| | before | after |
|---|---|---|
| whole-answer accuracy | .9184–.9271 | .9184–.9300 |
| strict accuracy | .9113–.9181 | .9113–.9215 |
| intent accuracy | .9738–.9796 | .9738–.9796 |
| refusal agreement | .9352–.9420 | .9386–.9454 |
| closed-set misses | 18–19 | 16–20 |
| two-name precision / recall | 1.000 / .7500–.7812 | 1.000 / .7500–.7812 |
| second names found | 24–25 of 32 | 24–25 of 32 |
| escalation rate | .1720–.1895 (59–65) | .1749–.1808 (60–62) |

**The verdict is NOISE on every figure** — `rake eval:classifier_compare` says
so, and every movement above is inside the band two unchanged runs of this bench
already span. The restoration is not sold as an improvement. What it is: the
request now asks the question it was measured asking, and there is a stored
reading either side saying what that cost, which is nothing.

## Why the second-name figure did not move, and it is not the wording

The stored readings of the scored arm find 28–30 of 32 second names where the
earlier text finds 24. That gap does not reach this bench, and the rows say why:

| | readings whose label carries a second name |
|---|---|
| escalated to the Mistral call by the two-name flag | 92 of 128 |
| composed by the cascade, which is where `also_named` is read | 36 of 128 |

**The escalation rule routes almost every two-name line away from the question
the wording governs.** A line that reads `named_more_than_one` at or above 0.5
never uses the cascade's own `also_named` answer: the Mistral call answers it.
So the `also_named` sentence can only reach about a quarter of the lines it was
measured on, and a change to it can only move a quarter of the figure. The
stored readings measured that question on every line because that simulation had
no escalation taking lines away from it.

## Which flag fires, per repetition

| rep | presence < 0.15 alone | two-name ≥ 0.5 alone | both | neither |
|---|---:|---:|---:|---:|
| 1 | 38 | 23 | 0 | 282 |
| 2 | 39 | 23 | 0 | 281 |
| 3 | 39 | 23 | 0 | 281 |
| 4 | 37 | 23 | 0 | 283 |

**The two flags never fire together.** Not once in 1,372 readings, on either
side. Presence carries about five escalations in eight; the two-name flag is
remarkably stable at 23 a repetition.

## The open question, settled as far as these rows can settle it

The scored readings escalate about 90 lines a repetition and this bench escalates
about 61. That gap is **not** the code-first gate, **not** the composition and
**not** the request wording:

* **not the gate.** The scored arm settled 65 of the 343 lines in code and sent
  278. Of those same 65 lines, this bench escalates **zero, in every repetition
  of both sides**. So the denominators already agree: on the 278 lines the
  scored arm sent, this bench escalates 59–65 against its 90–93.
* **not the composition.** Replaying the scored arm's own stored provider
  answers through the shipped composition reproduces 90, 90, 91, 93.
* **not the wording.** It is byte for byte the scored arm's now, pinned by
  `Playthrough::Classifier::RequestTest` against the stored request in
  `test/fixtures/files/scored_classifier_request.json`, and this set is what it
  reads.

**What the rows say it is: the readings themselves sit a little differently, and
both thresholds are cut through the middle of where the mass is.** 33 lines
escalate in the scored arm and not here; 4 the other way. They fall into two
families, and every one of them is within about 0.12 of its threshold:

* **20 `unresolved-*` lines** — the line reaches for something absent.
  `target_present` reads 0.07–0.15 in the scored arm and 0.15–0.29 here. A
  systematic shift up of roughly a tenth, across a cut at 0.15.
  (`hit Old Grenn` 0.07 → 0.17; `climb the Celestial Spire` 0.07 → 0.21;
  `talk to Odile Vance` 0.07 → 0.15.)
* **8 two-name lines** — `named_more_than_one` reads 0.51–0.62 in the scored arm
  and 0.30–0.45 here, across a cut at 0.5. (`take the ward stamp and the
  daybook` 0.60 → 0.40; `hit Neb and then the Justicar` 0.58 → 0.43.)

The mean readings are almost identical (`target_present` .560 against .554,
`named_more_than_one` .222 against .246) — it is the tails at the cuts that
moved.

**And the one thing left that could move them is the state.** The wording is
identical and the composition is pinned, so the request differs from the scored
arm's in exactly one place, and it does so in every position. Compared record by
record across all twelve staged positions, `Playthrough::Classifier::State`
differs from the state the scored arm sent in two ways and no others:

1. **`valid_intents` come back in a different order** — the scored arm sent
   `["take","examine"]` and `["drop","examine"]`; this one sends
   `["examine","take"]` and `["examine","drop"]`. 14 lists across the positions.
2. **An empty list is sent as `null` rather than `{}`** — 18 of them.

Neither is proven to move a Noul. Both are in every request, and nothing else
is. The state builder is where the next reading of this question belongs; it was
out of scope for the change this pair measures.

## Against the bands it was to be judged on

| | reading |
|---|---|
| this set, whole-answer | .9184–.9300 |
| the two-flag **simulation** over stored readings | .9300–.9359, 12–14 misses, .262–.271 escalation |
| the kept **Mistral-alone** row (`classifier-examine-wording-20260918`) | .9329–.9359 |

**This set does not reach the simulation's band and does not reach the
Mistral-alone row.** It is below both, as the shipped set was, and the residual
gap is the one described above. Both sets are kept as evidence for that reason.

## Spend

The after side is receipted at **$0.0902** on the escalation provider, read as
the movement in the account's own usage total across the run — 246 calls
actually made (245 escalations plus the excluded warm call), against the 1,372
readings the run scored. The before side was not bracketed the same way; at the
after side's receipted rate per call its 254 calls are about **$0.093**.

The System One request every line pays for is **unpriced** — the cost registry
has no row for that provider and this repository has no receipt for it. At the
rate the same eleven questions were receipted at during the design study it is
roughly $0.16 a run, which puts each side of this pair near $0.25 all in.

## Recompute for free

```bash
rake eval:classifier_compare BEFORE=classifier-cascade-before-20260919 AFTER=classifier-cascade-restored-20260919
rake eval:classifier_board SETS=classifier-examine-wording-20260918,classifier-cascade-before-20260919,classifier-cascade-restored-20260919
```
