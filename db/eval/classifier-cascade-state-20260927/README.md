# The cascade's kept set on the worlds with arcs

`Playthrough::Classifier::Cascade` in front of `mistralai/mistral-medium-3.1`,
System One answered by TypeSafe direct (`jev-1.13.0`), four repetitions, the 343
labelled lines at corpus digest `027013dd5a020328`. Every reading is kept, as
every cascade set's are. It replaces `classifier-cascade-state-20260919`, which
stays as history with the two sets it was judged against.

Re-bought because the worlds the lines are staged in gained arcs, and with
them a new thing on the floor of eight of the twelve staged positions (see
`db/eval/classifier-2026-09-26/README.md`). The request is the one the design
of record was scored on; only the state it describes moved with the world.
`classifier-cascade-before-20260919` and `classifier-cascade-restored-20260919`
measured request wording that no longer exists in the code, so they cannot be
re-bought and stay as the history they are.

## Verdicts

Against the set it replaces (different corpora, so read as the same request
on a changed world): NOISE on strict accuracy, accuracy, intent accuracy and
misses; refusal agreement 0.957 -> 0.954, WORSE, REAL (p=0.0286). It escalates
87 lines a repetition (349 over four), where the set before escalated 87-91.

Against today's model call alone (`classifier-2026-09-26`, same corpus):

```
  strict_accuracy      0.935 -> 0.936  BETTER   NOISE
  accuracy             0.936 -> 0.936  unchanged NOISE
  intent_accuracy      0.980 -> 0.974  WORSE    REAL (p=0.0286)
  refusal_agreement    0.948 -> 0.954  BETTER   NOISE
  closed_set_misses    15 -> 13        BETTER   INCONCLUSIVE
```

**On today's worlds the cascade's lead over the model call alone is inside the
noise**, where the sets of 2026-09-19 had it ahead with the bands apart.
`Eval::Classifier::KeptSetsTest` keeps asserting the old claim of the old files
and asserts of these only that the cascade is not behind on the medians.

## Spend

The escalations to Mistral cost $0.116584, provider-reported, over 349 calls
(`doc/evidence/seed-world-arcs-rebuy/cascade-receipts.json`). The TypeSafe
requests have no receipt endpoint used here and appear in no OpenRouter
reading, so their cost is not in any figure in this repository.
