# The classifier baseline on the worlds with arcs

The current single-arm before side: `mistralai/mistral-medium-3.1`, four
repetitions, the 343 labelled lines, bought after each checked-in world gained
an arc. It replaces `classifier-examine-wording-20260918`, which stays as
history.

## Why it was re-bought

The arcs added three things to the checked-in worlds -- a blank closure writ in
Ward Office 12, a hand-bell in the Causeway Court and a bearing book in the bell
chamber -- and each one is on the floor of a position the classifier is staged
at. Eight of the twelve staged positions list one of them, so the request the
classifier is sent moved (`v2:8fc01b135f1ed5fa` -> `v2:9c85ef6604541ebb`) with no
change to its instructions or schema.

## Three labels moved with the world, on the owner's ruling

Three lines were labelled against an office floor that had no writ on it, and
each now names it:

| line | was | now |
|---|---|---|
| `take a blank writ out of the press` | take -> nothing (unresolved) | take -> blank closure writ |
| `take the lot` | take -> ward stamp (and daybook) | take -> daybook (and blank closure writ), the other two pairs accepted |
| `take all of it` | take -> ward stamp (and daybook) | take -> daybook (and blank closure writ), the other two pairs accepted |

The corpus digest moved with them (`a259e93e6b865af1` -> `027013dd5a020328`).

## The readings were scored twice, and only the scoring moved

The calls were bought once. Scored against the old labels they read REAL worse
than the set before (strict 0.933 -> 0.925, misses 15 -> 18); every one of the
twelve readings that account for that is one of the three lines above, wrong in
all four repetitions because it named the writ. The same readings re-scored
against the new labels (`doc/evidence/seed-world-arcs-rebuy/rescore.rb`, no
model call) flip exactly those twelve and nothing else:

```
  strict_accuracy      0.933 -> 0.935  BETTER   NOISE
  accuracy             0.934 -> 0.936  BETTER   NOISE
  intent_accuracy      0.980 -> 0.980  unchanged NOISE
  refusal_agreement    0.950 -> 0.948  WORSE    REAL (p=0.0286)
  closed_set_misses    15 -> 15        unchanged NOISE
```

The set before kept no per-line readings, so it cannot be re-scored against the
new labels; the two sides above are therefore scored on different corpora and
the compare says so. `out_of_set` is a counter the set before never recorded,
so its 0 -> 62 is not a movement.

## Reproduce

```sh
rake eval:classifier_compare BEFORE=classifier-examine-wording-20260918 AFTER=classifier-2026-09-26
```
