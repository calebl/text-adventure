# The realization baseline on the worlds with arcs

The current before side for `Location::Generator`'s prompts:
`mistralai/mistral-medium-3.1`, four repetitions, all 29 cases, bought after
each checked-in world gained an arc and the items it needs. It replaces
`desires-scale-20260920`, which stays as history and remains the package the
branch cases were first bought in.

The seed edits moved the prompts the ordinary cases send -- the offline prompt
digest changed with no edit to `Location::Generator` -- so the stored set was no
longer a baseline for this tree. No realization prompt
text changed. The arcs themselves add no "Where This Story Is Going" block to
these cases: every beat a seed file writes is bound on load, and the block
asks only for an unbound one (`Location::GeneratorArcTest`).

## Verdict against the set before

NOISE on every check but one: `proposal_refused` 0.107 -> 0.000, BETTER, REAL
(p=0.0286). Latency reads REAL faster too; that is the provider on the day,
and the run was taken one call at a time. Full verdicts:
`doc/evidence/seed-world-arcs-rebuy/realization-inscription-comparison.log`.

`readings.json.gz` is the whole run and `requests.json` the branch requests it
sent, so `Eval::Realization::KeptSetTest` can recompute the summary and match
the requests to HEAD offline.

```sh
rake eval:realization_compare BEFORE=desires-scale-20260920 AFTER=realization-2026-09-26
```
