# The cascade's kept set — the request restored, wording and state

**This is the cascade's baseline.** `Playthrough::Classifier::Cascade` in front
of `mistralai/mistral-medium-3.1`, four repetitions, the 343 labelled lines at
corpus digest `a259e93e6b865af1`, with the System One request — **both halves of
it** — byte for byte the request the design of record was scored on.

It supersedes the earlier kept cascade set, which was taken before either half
was restored and reads about two points lower on every figure that matters.

## The three sides, and what each one changed

| | wording | state | whole-answer | strict | misses | second names | escalation |
|---|---|---|---|---|---|---|---|
| `classifier-cascade-before-20260919` | shipped | shipped | .9184–.9271 | .9113–.9181 | 18–19 | 24–25 | .1720–.1895 |
| `classifier-cascade-restored-20260919` | **restored** | shipped | .9184–.9300 | .9113–.9215 | 16–20 | 24–25 | .1749–.1808 |
| `classifier-cascade-state-20260919` *(this one)* | restored | **restored** | **.9388–.9417** | **.9352–.9420** | **12–13** | **27–28** | **.2536–.2653** |

The wording alone was **NOISE on every figure**. The state was the defect:

```
  strict_accuracy      0.918 -> 0.939  BETTER   REAL (p=0.0286)
  accuracy             0.924 -> 0.940  BETTER   REAL (p=0.0286)
  refusal_agreement    0.940 -> 0.957  BETTER   REAL (p=0.0286)
  closed_set_misses    18 -> 13        BETTER   REAL (p=0.0286)
```

## What was wrong with the state, and it was three things

Compared record by record against the arm's own stored requests for all twelve
staged positions. `Playthrough::Classifier::State` differed in three ways, and
in exactly three — correcting them makes all twelve byte-identical:

1. **`player_action` was second**, ahead of every record block, where the
   measured state puts it last.
2. **An empty block was left out** rather than sent as an empty map — 18 of them
   across the positions (`physical_actions` ×6, `available_items` ×6,
   `player_items` ×4, `other_characters` ×2). A block that is present and empty
   says *there is nothing of this kind here*; an absent block says nothing at
   all.
3. **`valid_intents` came back in enum order**, which puts `examine` ahead of
   `take` and ahead of `drop` — so a thing on the floor was listed as something
   to look at before something to pick up. 24 records. The measured order leads
   with the intent that defines the block.

None was a deliberate choice and none had a baseline.

## The open question, answered

**Yes. It escalates about 90 now.**

| | escalations a repetition, of 343 |
|---|---|
| the scored readings | 90, 90, 91, 93 |
| the two-flag simulation | .262–.271 |
| **this set** | 88, 87, 90, 91 — **.2536–.2653** |
| the set before the state was restored | 60–62 |

The gap that had stood since the cascade shipped is closed, and closing it was
worth 2 points of whole-answer accuracy, 5 closed-set misses and 3 second names.

## Which flag fires, per repetition

| rep | presence < 0.15 alone | two-name ≥ 0.5 alone | both | neither | escalated |
|---|---:|---:|---:|---:|---:|
| 1 | 56 | 32 | 0 | 255 | 88 |
| 2 | 57 | 30 | 0 | 256 | 87 |
| 3 | 59 | 31 | 0 | 253 | 90 |
| 4 | 59 | 32 | 0 | 252 | 91 |

**The two flags still never fire on the same line** — not once in 1,372
readings here, nor in 2,744 across the two earlier sides.

## The cascade is no longer behind the model call

| | this set | the kept model-alone row |
|---|---|---|
| whole-answer | **.9388–.9417** | .9329–.9359 |
| closed-set misses | **12–13** | 15–16 |
| refusal agreement | **.9556–.9590** | .9488–.9522 |
| median latency | **0.40–0.42s** | 0.53–0.61s |
| p95 latency | 1.15–1.33s | **0.90–1.02s** |

`rake eval:classifier_compare BEFORE=classifier-examine-wording-20260918
AFTER=classifier-cascade-state-20260919` returns **REAL BETTER** on accuracy,
refusal agreement and closed-set misses, and REAL better on median latency.

**The one figure that is REAL WORSE is p95 latency**, and it is worse by
construction rather than by accident: an escalated line makes two calls in
sequence, and about a quarter of the lines escalate. The median turn got faster
and the worst turn in twenty got slower. That is the trade the cascade is, and
it should be stated that way.

## Where the second names come from, which is worth knowing before editing `also_named`

| | readings whose label carries a second name |
|---|---|
| escalated to the model call by the two-name flag | 117 of 128 |
| composed by the cascade, where `also_named` is read | 11 of 128 |

The two-name flag routes nearly every two-name line to the model call, so the
cascade's own `also_named` answer is read on about one line in twelve of the
ones it was measured on. **A change to the `also_named` wording can only move
that eleventh.** This is why restoring that sentence moved the second-name count
by nothing, and why restoring the state moved it from 24–25 to 27–28: the flag
started firing on the lines it was supposed to fire on.

## Spend

Receipted at **$0.1253** on the escalation provider — 356 calls actually made
(355 escalations plus the excluded warm call) against the 1,372 readings scored,
read as the movement in the account's own usage total, re-read until it stopped
moving. It costs more than the earlier sides because it escalates more, which is
the point of it.

The System One request every line pays for is **unpriced**: no row in the cost
registry and no receipt endpoint used here.

## Recompute for free

```bash
rake eval:classifier_compare BEFORE=classifier-cascade-restored-20260919 AFTER=classifier-cascade-state-20260919
rake eval:classifier_compare BEFORE=classifier-examine-wording-20260918 AFTER=classifier-cascade-state-20260919
rake eval:classifier_board SETS=classifier-examine-wording-20260918,classifier-cascade-before-20260919,classifier-cascade-restored-20260919,classifier-cascade-state-20260919
```
