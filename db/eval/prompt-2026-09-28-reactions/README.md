# prompt-2026-09-28-reactions

The main prompt corpus, re-bought at four repetitions on the shipped model
after the people in a room began reacting to the party walking in. The
engine's reactions step writes their rows before the arrival is asked for,
and the arrival request tells them in an "## As You Come In" block after the
records.

No instruction changed. Nine of the corpus's twelve `move` cases walk into a
room where somebody reacts, so their arrival request gains the block; the
designated `move` case (`move-back-to-court`) gains Ammon Brace warning the
player about the drop on the way to The Vestry Hulk. Every other case sends
the bytes it sent under `prompt-2026-09-28`, the baseline this replaces.

`rake eval:prompt_compare BEFORE=prompt-2026-09-28 AFTER=prompt-2026-09-28-reactions`
is recorded below.

Every check reads NOISE but `item_not_held`, which reads REAL better (0.050
-> 0.033). Every one of its flags in this set is on a take, examine or look
case (`take-index-*`, `examine-apron-plain`, `examine-stamp-plain`,
`other-look-around`), none of which walks into a room, so their requests did
not move and the change did not cause it. Median
and p95 latency read REAL faster (1.79s -> 1.60s, 2.46s -> 2.15s), which is
provider timing on the day. Two calls fell back to the engine's own words
(`failures` 0 -> 0 at the median, inside the unchanged runs' span).

```
------------------------------------------------------------------------------
PROMPT BENCH: prompt-2026-09-28 -> prompt-2026-09-28-reactions
Exact rank test at p <= 0.05, 4 repetitions a side minimum.
------------------------------------------------------------------------------
schema request: v1:08dd3f5abd9ac041
prompt-2026-09-28: mistralai/mistral-medium-3.1 | corpus dfd1756a8f1f91b8 | prompt c0364ac029af1838 | 4 reps
schema request: v1:9a85b9d4a0c663ab
prompt-2026-09-28-reactions: mistralai/mistral-medium-3.1 | corpus dfd1756a8f1f91b8 | prompt d9cbba88a8e3eecb | 4 reps
Latencies are WARM-CACHE figures -- each arm's first call is timed apart and excluded.

This is a PROMPT comparison on one model: c0364ac029af1838 -> d9cbba88a8e3eecb.

MODEL  mistralai/mistral-medium-3.1
  unrecorded_departure       0.000 -> 0.000  unchanged NOISE (inside the 0.000 the unchanged runs already spanned)
  unrecorded_arrival         0.000 -> 0.000  unchanged NOISE (inside the 0.000 the unchanged runs already spanned)
  item_not_held              0.050 -> 0.033  BETTER    REAL (p=0.0286)
  take_denied                0.056 -> 0.056  unchanged NOISE (inside the 0.000 the unchanged runs already spanned)
  pickup_invented            0.000 -> 0.000  unchanged NOISE (inside the 0.000 the unchanged runs already spanned)
  inscription_misquoted      0.000 -> 0.000  unchanged NOISE (inside the 0.000 the unchanged runs already spanned)
  truncated_prose            0.000 -> 0.000  unchanged NOISE (inside the 0.000 the unchanged runs already spanned)
  third_person_protagonist   0.000 -> 0.000  unchanged NOISE (inside the 0.011 the unchanged runs already spanned)
  blow_contradicted          0.000 -> 0.000  unchanged NOISE (inside the 0.000 the unchanged runs already spanned)
  toll_contradicted          0.000 -> 0.000  unchanged NOISE (inside the 0.000 the unchanged runs already spanned)
  throw_contradicted         0.000 -> 0.000  unchanged NOISE (inside the 0.000 the unchanged runs already spanned)
  body_contradicted          0.000 -> 0.000  unchanged NOISE (inside the 0.000 the unchanged runs already spanned)
  beat_contradicted          0.000 -> 0.000  unchanged NOISE (inside the 0.000 the unchanged runs already spanned)
  refusals                   0 -> 0  unchanged NOISE (inside the 1.000 the unchanged runs already spanned)
  failures                   0 -> 0  WORSE     NOISE (inside the 1.000 the unchanged runs already spanned)
  omitted_fields             0 -> 0  unchanged NOISE (inside the 0.000 the unchanged runs already spanned)
  cap_hits                   0 -> 0  WORSE     NOISE (inside the 2.000 the unchanged runs already spanned)
  latency_median             1.79s -> 1.60s  BETTER    REAL (p=0.0286)
  latency_p95                2.46s -> 2.15s  BETTER    REAL (p=0.0286)
  output_tokens              12876 -> 12749  reported  NOISE (inside the 342.000 the unchanged runs already spanned)
  words                      98 -> 98  reported  NOISE (inside the 6.000 the unchanged runs already spanned)
  commitments                3.416 -> 3.374  reported  NOISE (inside the 0.264 the unchanged runs already spanned)

A REAL verdict on a CHECK is what means a prompt change worked. Read `commitments`
beside it: a fall in every rate with a fall in that is prose that says less, which is
the one way to improve these numbers without improving the game (Eval::Richness).
Everything INCONCLUSIVE at these sample sizes means: not enough repetitions.
Confirm a REAL verdict with `rake eval:run` before believing it.
------------------------------------------------------------------------------
```
