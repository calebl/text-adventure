# Final merge-chain rebase

The main revision is recorded in `verification.json`. Documentation and
measurement entries preserve all landed benchmarks. Main's shared identity
helper, task definitions and kept-set tests remain unchanged. The arrival kept
set is byte-identical to the original purchase; no paid calls were made.

Firstmate requested focused local checks for this rebase: all `test/lib/eval`
tests with `PARALLEL_WORKERS=2`, RuboCop, Zeitwerk and `eval:manifest`. Logs are
kept here. The eval tests include offline equality checks for every kept arrival
request. Firstmate watches the full CI suite and handles the merge.
