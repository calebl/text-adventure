# The classifier baseline after the `examine` wording change

This is the current before side for the next change to
`Playthrough::Classifier::INSTRUCTIONS`. It replaces
`physical-classifier-final-20260914`, which remains history and remains the
judged R02 prompt: the only thing that moved between them is the `examine`
criterion, and that is what the pair of sets beside this file measures.

## What changed in the prompt

The criterion read *"they are looking at something more closely"* — **something**,
an object — while the corpus labels a targetless look at the room as `examine`.
It now reads *"they are looking at something more closely, or looking around the
place in general"*. The same words are in
`Playthrough::Classifier::Request::INTENT_CRITERIA`, so the two readers of a
typed line cannot disagree about what `examine` means.

## The sets

| set | wording | schema request |
|---|---|---|
| `classifier-examine-before-20260918` | before | `v2:8cab930ca8f08d00` |
| `classifier-examine-wording-20260918` *(this one)* | after | `v2:8fc01b135f1ed5fa` |

Both are `mistralai/mistral-medium-3.1`, four repetitions, the same 343 lines at
corpus digest `a259e93e6b865af1`, the same scorer, no other change. Recompute
the verdict with no key and no calls:

```bash
rake eval:classifier_compare BEFORE=classifier-examine-before-20260918 AFTER=classifier-examine-wording-20260918
```

## The verdict: NOISE, on every metric

```
  strict_accuracy      0.937 -> 0.933  WORSE    NOISE (inside the 0.020 the unchanged runs already spanned)
  accuracy             0.939 -> 0.934  WORSE    NOISE (inside the 0.015 the unchanged runs already spanned)
  intent_accuracy      0.977 -> 0.980  BETTER   NOISE (inside the 0.003 the unchanged runs already spanned)
  refusal_agreement    0.956 -> 0.950  WORSE    NOISE (inside the 0.020 the unchanged runs already spanned)
  closed_set_misses    13 -> 15  WORSE    NOISE (inside the 5.000 the unchanged runs already spanned)
  latency_median       0.55s -> 0.55s  WORSE    NOISE
  latency_p95          0.98s -> 0.96s  BETTER   NOISE
  failures             0 -> 0  unchanged
```

**So the change is not sold as an improvement and must not be.** What it is: a
criterion that now says what the labels already assume, measured to cost nothing
on the corpus at four repetitions a side. Two identical runs of this bench
disagree by more than any of the movements above — which is the whole reason the
verdict column exists.

The offline floor is unmoved and could not have moved: `Eval::Classifier::Offline`
is the fixed grammar, which reads no instructions at all. `offline.json` beside
this file is that floor, recomputable for free with `rake eval:classifier_offline`.
