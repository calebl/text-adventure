# The classifier baseline: `throw` in the enum, on the worlds with arcs

The current single-arm before side: `mistralai/mistral-medium-3.1`, four
repetitions, all 351 labelled lines at corpus digest `da78f0dd2cf9c1f7`, request
identity `v2:ba3b467f3436519f` -- the request the code sends today, which is
the classifier that can answer `throw`, staged on the checked-in worlds after
each gained an arc.

## Why it exists

Two changes landed at once and each had its own set on the other's old
footing: `classifier-throw-after-20260926` measured `throw` on the worlds
before they had arcs, and `classifier-2026-09-26` measured the worlds with arcs
before `throw` joined the enum. Neither matched the merged request, so this is
the one run that does. Both stay as history; `Eval::Classifier::KeptSetsTest`
reads each at the corpus it was scored on.

The corpus is the throw lines plus the three labels that moved to name the
writ the Unrecorded Hour's arc put in the office (see
`db/eval/classifier-2026-09-26/README.md` for those three and why).

## Verdicts

Against `classifier-throw-after-20260926` (the same request shape, on the
worlds before arcs; the corpora differ by those three labels): **NOISE on every
figure** -- strict accuracy 0.938 -> 0.936, accuracy 0.940 -> 0.937, intent
accuracy 0.983 -> 0.982, refusal agreement 0.954 -> 0.948, misses 15 -> 15.

Against `classifier-2026-09-26` (the worlds with arcs, before `throw`): NOISE on
strict accuracy, accuracy, refusal agreement and misses; intent accuracy 0.980
-> 0.982, BETTER, REAL (p=0.0286).

## How the spend was bounded

Run one call at a time. A first attempt at two calls in flight was stopped by
its own ledger after 552 of 1373 calls, because each open call held a
reservation of the model's whole output allowance ($0.21); the bench does not
resume, so those calls are spent and not in this set. For this run the open
reservation was a stated bound instead: **$0.006 a call, ten times the highest
charge observed for this request shape ($0.0005968 over the 551 settled calls
of that attempt)**, with any call returning more than it halting the run. The
ledger's settled spend plus the one open reservation never passed the group's
ceiling. This run: 1373 calls, $0.468936 provider-reported
(`doc/evidence/seed-world-arcs-rebuy/classifier-final-rerun-receipts.json`).

```sh
rake eval:classifier_compare BEFORE=classifier-throw-after-20260926 AFTER=classifier-2026-09-27
```
