# The realization baseline with each place's sort and density

The current before side for `Location::Generator`'s prompts:
`mistralai/mistral-medium-3.1`, four repetitions, all 29 cases. It replaces
`realization-2026-09-26`, which stays as history.

What moved is the schema and nothing else. The exits call asks `kind` and
`density` for each place it names, and a building's place call asks
`place_kind` (`Location::Kind`); no prompt message changed, so the prompt
digest is `5f42d5c63ea43a36` on both sides and only the schema request
identity moved, `v1:526e8a8e06253c4b` -> `v1:ed784086d87b830c`.

## Verdict against the side before

The before side, `realization-before-2026-09-28`, was bought the same day at
the tree the change was made on, with that tree's schema, and is not kept:
its figures are in the comparison log. NOISE on every figure, checks and
reported counts alike; nothing moved past what the unchanged runs already
span. One realization of the after side failed on a reply cut off
mid-string (`JSON::ParserError`, `quay-dangerous-back-room`, repetition 3),
which reads as `failures 0 -> 0`, NOISE: the unchanged runs have spanned one.

```sh
rake eval:realization_compare BEFORE=realization-before-2026-09-28 AFTER=realization-2026-09-28
```

Logs: `doc/evidence/dense-rooms-kinds/`. The two sets were written under
working names and renamed before this one was kept; the run logs carry the
kept names and are otherwise as printed.

## What it cost

`receipts.json`. The credits read before and after each side, on an account
other work shares, moved $0.384 for the before side and $0.399 for this one,
$0.783 for both, against a cap of $1.00; the registry priced them at $0.3792
and $0.3780.

`readings.json.gz` is the whole run and `requests.json` the branch requests it
sent, so `Eval::Realization::KeptSetTest` can recompute the summary and match
the requests to HEAD offline.
