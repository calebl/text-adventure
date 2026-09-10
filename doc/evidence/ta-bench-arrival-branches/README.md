# Arrival bench evidence

The scratch database was `tmp/arrival/bench.sqlite3` in this disposable worktree.
`rake ruby_llm:load_models` loaded the registry before pricing. No shared game
database was accessed. No server or browser was started.

- `preflight.txt`: retained study annotations beside lexical proxies, followed by
  the original estimate, saved before the first paid call.
- `paid-run.log`: the initial run, with its printed estimate.
- `repair-estimate.json`, `repair-run.log`, `repair_pending.rb`: the pending-toll
  fixture correction. The first fixture put the room's `flooded` hazard on an
  edge; the corrected fixture uses the edge's `undertow`. The source-consistency
  test now checks the toll against the actual source. Only that case was bought
  again, with the same cumulative ledger.
- `budget.json`: every attempt and its provider/registry/conservative accounting.
- `receipts-summary.json`: spend across all ledger entries, including superseded
  readings. The kept set retains those readings outside its scored `rows`.
- `precision.json`: lexical fact-missing agreement and misses against the retained
  independent reader. `test/lib/eval/arrival/scorer_test.rb` recomputes this table.
  Wound/floor and grammar cues have constructed examples and explicit misses;
  they have no independently annotated semantic precision claim.
- `board.txt`, `digests.txt`, `self-compare.json`: offline command outputs.
- `estimate.txt`: the standing estimator after the run; the pre-buy estimate is
  separately retained above.
- `manifest.txt`: the final measurement manifest.
- `arrival-tests.log`, `test.log`, `rubocop.log`, `zeitwerk.log`, `brakeman.log`:
  validation outputs. The Rails suite includes the engine sweep.

The kept set at `db/eval/arrival-branches/arrival.json` is authoritative. Its
`budget.entries` include all spending, while `rows` are the current baseline.
The main prompt corpus and all production prompts, schemas, engine files and
migrations are unchanged. The ordinary main move set's stale scaffold belongs
to the separate re-baseline task.

The request-identity helper is byte-identical to the implementation in
https://github.com/calebl/text-adventure/pull/177. This branch is self-contained;
the identical helper should reconcile directly when that sibling lands. The
stager/budget layout follows https://github.com/calebl/text-adventure/pull/178,
with no runtime dependency on its dialogue classes. No competing identity
algorithm was introduced.
