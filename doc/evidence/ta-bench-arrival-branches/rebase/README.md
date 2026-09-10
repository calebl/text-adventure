# Rebase verification

Rebased on the main commit recorded in `verification.json`. Both the dialogue
and arrival sections of `EVALUATION.md` are preserved. Main's measurement entries
remain, and the duplicate shared-helper entry was removed. Main's identity
helper and tests, task definitions, and other kept-set tests are unchanged.

The arrival kept set is byte-identical to the original commit. The offline
arrival tests rebuild every request against main's shared helper; `digests.txt`
is identical to the original digest output. No paid calls were made.

The four required gates have their own logs in this directory. The original
purchase evidence remains unchanged beside it.

The initial default-worker suite is retained as `test-contended.log`: its only
failure was the existing wall-clock audit performance assertion while other
repository suites were running concurrently. `test.log` is the full rerun with
`PARALLEL_WORKERS=2`; no test or threshold was changed.
