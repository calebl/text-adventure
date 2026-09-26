# The classifier baseline after `throw` joined the intent enum

This is the current before side for the next change to
`Playthrough::Classifier::INSTRUCTIONS` or `Playthrough::IntentSchema`. It
replaces `classifier-examine-wording-20260918`, which remains history and remains
the Mistral-alone row the cascade sets were judged against on the 343-line
corpus.

## What changed in the request

- `throw` was appended to `Playthrough::IntentSchema::INTENTS`, after `other`,
  so every earlier word keeps its index in the confusion matrix.
- The schema gained a `thrown_at` field: who or which way out the thing was
  aimed at, out of the same closed set, `nothing` otherwise.
- The instructions gained a `throw` line in the intent list after `use`, and a
  paragraph after the `use` paragraph saying what `target` and `thrown_at` hold
  for a throw, that a throw at a wall, machine, fixture or the room answers
  `thrown_at` with `nothing`, and that "throw the switch" is `other`.

The System One request is unchanged: the typed reader's intent question does not
offer `throw`, and `test/fixtures/files/scored_classifier_request.json` still
matches it byte for byte.

## The corpus

Eight throw lines were added, taking the corpus from 343 lines to 351 (digest
`1ebd2f0c35908933`): a throw resolved at a person (three lines), through a way
out (two), at scenery (one, which earns a refusal), and two "throw the switch"
lines labelled `other`. Both sides below were scored on the 351 lines.

## The sets

| set | request | schema request |
|---|---|---|
| `classifier-throw-before-20260926` | before: no `throw` | `v2:8fc01b135f1ed5fa` |
| `classifier-throw-after-20260926` *(this one)* | after | `v2:01028d942ffc85a3` |

Both are `mistralai/mistral-medium-3.1`, four repetitions, the same scorer.
Recompute the verdict with no key and no calls:

```bash
rake eval:classifier_compare BEFORE=classifier-throw-before-20260926 AFTER=classifier-throw-after-20260926
```

## The verdict

```
  strict_accuracy      0.915 -> 0.938  BETTER   REAL (p=0.0286)
  accuracy             0.919 -> 0.940  BETTER   REAL (p=0.0286)
  intent_accuracy      0.963 -> 0.983  BETTER   REAL (p=0.0286)
  refusal_agreement    0.940 -> 0.954  BETTER   REAL (p=0.0286)
  closed_set_misses    15 -> 15  BETTER   NOISE (inside the 6.000 the unchanged runs already spanned)
  out_of_set           62 -> 60  BETTER   REAL (p=0.0286)
```

p=0.0286 is the smallest p-value four runs against four can give: every
repetition after the change scored above every repetition before it.

On the throw lines alone, over all four repetitions (the `throw`, `throw-exit`,
`throw-scenery` and `throw-idiom` rows of the bench's BY SHAPE table): 4/32
before, 32/32 after. Before the change the classifier could not answer `throw`,
so the only readings it got right were four of the eight on the two `other`
lines.

**Rep 3 of the after side lost 105 of its 351 calls to provider rate limiting**
(`RubyLLM::RateLimitError`), so that repetition's figures are over the 246 lines
that were answered. The before side had no failures. The run was not bought
again, because a second after side would have gone over the spend approved for
this measurement.

`offline.json` beside this file is the fixed-grammar floor on the 351 lines,
recomputable for free with `rake eval:classifier_offline`. The grammar reads no
instructions, so the change could not move it.
