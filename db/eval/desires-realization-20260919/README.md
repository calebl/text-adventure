# Objects-of-desire realization baseline

This is the complete room-realization baseline for the tree after characters
acquired four objects of desire and two pursuit labels. It contains one pinned
`mistralai/mistral-medium-3.1` arm, four complete repetitions of the 29-case
corpus, 116 measured realizations, and one successful warm-up. No measured
reading failed, refused, rotated, made an extra call, or omitted a required
field.

The plain `desires-after` result established the matched verdict but did not
retain provider receipts or a budget ledger. Those readings therefore remain
historical evidence and were not relabelled. This package was bought in the
recording form used here: every provider request and answer is in
`provider-readings.jsonl.gz`, every full bench row is in `readings.json.gz`, and
`realization.json` is the compact summary recomputed from those rows.

## What the comparison says

`comparison.txt` and `verdicts.json` are oriented
**physical-realization-20260910 -> desires-realization-20260919**, the old
baseline to this package. Every behavioral and operational check is **NOISE**.
The neutral output-volume figure is **REAL**: median output tokens rise from
22,357 to 27,885 per complete pass, +5,528 (p=.028571).

`matched-verdicts.json` compares the unchanged `desires-before` arm with this
new sample of the wider answer. It finds `cap_hits` 1.5 -> 4,
`proposal_refused` 0.0180 -> 0.03775, and p95 latency 14.56s -> 17.20s as
**REAL**; median latency is noise at 7.12s -> 7.12s. Output rises from 22,338.5
to 27,885 tokens. The originally judged pair in `desires-before` and
`desires-after` reported the same cost in its own sample as cap hits 1 -> 3,
proposal refusal 0.018 -> 0.040, median latency 7.12s -> 8.31s, and output
22,338 -> 27,690. People named, offered, and accepted remain unchanged in both
comparisons.

These are costs of a wider structured answer, not evidence of behavioral
improvement. The rubric does not score whether the four desires are coherent,
dramatically useful, or distinct enough; this package makes no such claim.

## Provenance and guard fields

`source-manifest.json` records the producer commit, every relevant source hash,
the corpus digest, prompt and instruction digests, prompt shapes, the shared
schema-request identity, the branch-request identity, gem versions, and the
single-provider model pin. `run-provenance.json` records the allocation,
execution shape, script hashes, interruption, and limitations.

The kept-set guard reads these fields from the following artifacts:

- `realization.json`: package name, arm, actual answering model, four
  repetitions, stable prompt and instruction digests, current corpus identity,
  current schema identity, and the compact figures;
- `requests.json`: all fixed branch requests and their identity;
- `readings.json.gz`: four paid rows per case, captured requests, admissions,
  answers, and the rows from which the compact figures are recomputed;
- `receipts.json`: the successful warm-up, per-reading call/token/cost totals,
  the $1.50 authorization, conservative accounting, and before/after OpenRouter
  account snapshots; and
- `Eval::MEASUREMENT_FILES`: the durable declaration that these artifacts are
  part of the measurement.

The first warm-up attempt received a rate-limit response before a usage receipt
was available. It remains an unknown conservative reservation in
`receipts.json`; the successful replacement and all measured readings are fully
receipted. Registry/provider-priced successful calls cost $0.324783, while the
local ledger accounts $0.465313 including that unknown reservation. The
OpenRouter account delta is retained only as a bracket because other account
use can occur concurrently.

During offline replay, in-memory schemas retain symbol keys while frozen JSON
has string keys. `replay.rb` applies the existing
`Eval::Realization::BranchRequests.canonical` conversion before comparison;
this changes representation only, not system, user, schema content, or engine
admissions. Provider history is retained from the live request capture because
an offline stub does not append the provider's assistant message.

With an isolated prepared test database, the replay makes no model call:

```sh
RAILS_ENV=test DATABASE_URL=sqlite3:/tmp/desires-realization-replay.sqlite3 bin/rails db:prepare db:seed
RAILS_ENV=test DATABASE_URL=sqlite3:/tmp/desires-realization-replay.sqlite3 bin/rails runner db/eval/desires-realization-20260919/replay.rb
```
