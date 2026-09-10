# Inscriber measurement evidence

The disposable worktree's own database was prepared, then its model registry was
loaded with `bin/rake ruby_llm:load_models`. No primary-checkout database was
opened. `estimate.json` was written before `run.log`'s first paid call. Pricing
uses the pinned model's registry rates and conservative byte-based allowances.
`receipts.json` is a summary of the kept set's per-response token receipts;
recompute those from `db/eval/inscription-2026-09-10/inscription.json`.

The set includes rejected output as well as accepted words. A production
verification rejection does not turn into clean prose or zero-cost usage.
No cases were omitted or rebought. Human fit remains unjudged. The self-compare
in `null-check.log` is an offline plumbing check, not an independently bought
null experiment; unavailable punctuation readings correctly stay inconclusive.

Validation commands and output:

- `bin/rails test`: `tests.log` (includes the engine sweep).
- `bin/rails test test/lib/eval/inscription`: `bench-tests.log`, rerun after
  adding the final incomplete-set comparison guard.
- `bundle exec rubocop`: `rubocop.log`.
- `bin/rails zeitwerk:check`: `zeitwerk.log`.
- `bin/brakeman --no-pager`: `brakeman.log`.
- `bin/rake eval:estimate`: `all-estimates.log`.
- `bin/rake eval:inscription_digest`: `digest.json`.
- `bin/rake eval:inscription_score SET=inscription-2026-09-10`: `board.log`.
- `bin/rake eval:manifest`: `manifest.log`.

After rebasing on main, `Eval::RequestIdentity` and its tests use main's
unchanged copies. Production inscriber instructions and schema are unchanged.
The `rebase-*` logs record the repeated required gates and offline digest.
The digest matches the original evidence; the kept set was not rebought.
