# The cascade, measured on the request wording as it shipped

The **before** side of the request-wording restoration. `Playthrough::Classifier::Cascade`
in front of `mistralai/mistral-medium-3.1`, four repetitions, the 343 labelled
lines at corpus digest `a259e93e6b865af1` — the same arm, corpus and scorer as
`classifier-examine-wording-20260918`, which is the Mistral-alone row this
cascade is judged against.

The wording it was taken on is the one that shipped: the `also_named` and
per-action target sentences of an earlier revision of the arm the design of
record was scored on. `classifier-cascade-restored-20260919` beside this file is
the same run with those eight sentences restored — and it reads the same, which
is what sent the diagnosis on to the STATE.
`classifier-cascade-state-20260919` is where that ended up and is the cascade's
kept set; read its README for what was actually wrong.

## The figures

| | this set |
|---|---|
| whole-answer accuracy | .9184–.9271 |
| strict accuracy | .9113–.9181 |
| intent accuracy | .9738–.9796 |
| refusal agreement | .9352–.9420 |
| closed-set misses | 18–19 |
| two-name precision / recall | 1.000 / .7500–.7812 (24–25 of 32) |
| escalation rate | .1720–.1895 (59–65 lines of 343) |

## The rows are kept, and that is the point of this set

Every reading carries `resolved_by` and the two Noul readings the cascade acted
on (`target_present`, `named_more_than_one`). No other kept classifier set
carries rows; this pair does because the open question about the cascade is
**which flag fires on which lines**, and four aggregate numbers a side cannot
answer it. The flags, per repetition:

| rep | presence < 0.15 alone | two-name ≥ 0.5 alone | both | neither |
|---|---:|---:|---:|---:|
| 1 | 41 | 24 | 0 | 278 |
| 2 | 42 | 23 | 0 | 278 |
| 3 | 40 | 24 | 0 | 279 |
| 4 | 35 | 24 | 0 | 284 |

**The two flags never fire on the same line.** Not once in 1,372 readings.

## Recompute for free

```bash
rake eval:classifier_compare BEFORE=classifier-cascade-before-20260919 AFTER=classifier-cascade-restored-20260919
```

`offline.json` is the fixed-grammar floor these calls are bought against,
recomputable with `rake eval:classifier_offline`. It is identical in both sets
and could not differ: the grammar reads no instructions at all.
