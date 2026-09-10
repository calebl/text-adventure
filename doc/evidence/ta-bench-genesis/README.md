# Genesis bench evidence

`estimate.log` was written before the purchase; the purchase command also
printed its precise allowance before its first call in `purchase.log`.
`model-registry.log` records the required offline registry load. The actual
receipts live with each reading in `db/eval/genesis-before/genesis.json`;
`receipts.json` sums those recorded prices and token counts. No other paid
run or warm-up was made for this task.

The first purchase board exposed an enum-key/label comparison error in the
instrument: `Character#sex` returns a key while the character prompt states the
stored label. `Scorer` now reads `Character.sexes` to compare them. This changed
no prompt and needed no paid replay. `board.log` is the corrected offline
reading, and the regression is in `ScorerTest`. The capture's `after.valid`
field is not scored: construction of an unsaved character beside the quest's
fixed upstream player is not a test of admitting another protagonist. Current
capture no longer asks that validator. No provider answer or receipt was edited.

`digest-before.json` is the offline identity assembled before purchase.
`KeptSetTest` checks every kept request against the live builders, including
schemas and restored assistant messages. Main was fetched before purchase;
the shared schema-digest instrument had not landed. This bench therefore uses
explicit canonical JSON identity for all these inputs.

`unit.log`, `test.log`, `rubocop.log`, `zeitwerk.log` and `brakeman.log` are the
validation outputs. `null.log` compares the baseline with itself using the same
noise protocol as the other benches. `manifest.log` is the measurement file
manifest; every newly added bench implementation file and its kept baseline
are included.

The raw output is retained because the checks measure record fidelity, not
fiction quality. The human-scored lab remains outside this slice. No production
prompt, schema, engine behavior, world seed, migration or update step changed.
