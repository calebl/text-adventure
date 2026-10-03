# The realization baseline with rooms furnished from their kits

The current before side for `Location::Generator`'s prompts:
`mistralai/mistral-medium-3.1`, four repetitions, all 29 cases. It replaces
`realization-2026-09-28`, which stays as history.

What moved is the detail prompt, in a furnished room only. Each corpus case
now names the `kind` and `density` its room would have been dealt, so the bench
stages rooms that `Item::Kit` furnishes before the writer is asked anything,
and the detail prompt states what is there in the "Already Here" block. In a
furnished room the floor list's first line also reads "..., besides the ones
Already Here above: those are written already, and a thing named again is not a
new one." A room with no kind is asked exactly what it was before.

## Verdict against the side before

The before side, `realization-before-2026-10-02`, was bought at the tree
that added the corpus's `kind` and `density` and nothing else (every room
carried its word, none was furnished, every prompt the old baseline's), and is
not kept: its figures are in the comparison logs. Against it:

- `things_furnished` 0 -> 10, REAL: the kit's rows, read off the records.
- `items_named` 1.66 -> 0.41, REAL: the writer names far fewer things of its
  own in a room already holding ten. Of the 47 it named over the run, 3 were
  copies of a kit row, so about 0.38 a room are its own; the before side's
  were 1.65. The owner accepted this as measured (2026-10-02).
- `output_tokens` down, REAL; every check NOISE (`no_new_ground` 0.367 ->
  0.467, INCONCLUSIVE).

```sh
rake eval:realization_compare BEFORE=realization-before-2026-10-02 AFTER=realization-2026-10-02
```

A first after side, `realization-first-after-2026-09-28`, was bought with the
block alone, before the floor list's sentence existed, and is not kept. It
read `name_already_spoken_for` 0.000 -> 0.317, WORSE and REAL: the writer
re-listed the block's loose things as its own, 143 of 168 proposals, so its own
new things fell to 0.22 a room. That finding is what the sentence answers, and
it is `realization-first-comparison.log`.

Logs: `doc/evidence/dense-rooms-furnished/`. The sets were written under working
names and renamed before this one was kept; the run logs carry the kept names
and are otherwise as printed.

## What it cost

`receipts.json`. The credits read around each run, on an account other work
shares, moved $0.335 for the before side, $0.324 for the first after side and
$0.418 for this one, $1.077 for the three, against a cap of $1.20 (raised from
$1.00 by the owner for the second after side); the registry priced them at
$0.317, $0.301 and $0.351.

`readings.json.gz` is the whole run and `requests.json` the branch requests it
sent, so `Eval::Realization::KeptSetTest` can recompute the summary and match
the requests to HEAD offline.
