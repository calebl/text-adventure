# Objects-of-desire dialogue baseline

This package promotes the complete `desires-after` dialogue recording as the
standing baseline. It contains the same nine fixed fictional exchanges, four
repetitions, 36 readings and 72 two-pass calls on pinned
`mistralai/mistral-medium-3.1`. The source already retained every system/user
request, emitted schema, history, raw answer, actual model, engine receipt,
token/cost receipt, and budget entry, so buying an identical second sample
would add cost without filling a provenance gap. `dialogue.json` preserves those
paid rows; promotion itself made no model call.

Both comparisons say **NOISE** for every available metric.
`comparison.json` is oriented **physical-dialogue-20260910 ->
desires-dialogue-20260919**, and `matched-comparison.json` is oriented
**desires-before -> desires-dialogue-20260919**. Contradiction remains
**unavailable**, never zero, because no signed human annotation set was
supplied.

This evidence covers bounded dialogue actions, displayed exchange length, and
request identity. It does not score whether the new desires produce better
voice, personality, memory across turns, long-term behavior, or general
realism, and no behavioral improvement is claimed.

## Provenance and guard fields

`source-manifest.json` records the producer commit and source hashes, source
measurement hash, corpus digest, request bundle, prompt and schema digests, gem
versions, and the pinned single-provider model. `run-provenance.json` records
the original completion time, promotion time, execution shape, reuse decision,
and limitations. `receipts.json` summarizes the per-call receipts and embeds
the original conservative budget.

The kept-set guard gets its required fields from:

- `dialogue.json`: model, corpus, four repetitions, all 36 rows, two calls per
  row, actual answering models, request digests, exact requests, engine facts,
  and the budget entries;
- `Eval::Dialogue::Version.rebuild`: today's system, user, schema, history and
  engine facts for every retained answer;
- `receipts.json`: registry-priced and provider-reported call totals plus the
  authorized/accounted budget fields; and
- `Eval::MEASUREMENT_FILES`: the durable declaration that the promoted result
  and provenance belong to the measurement.

The retained calls cost $0.03391808 at their recorded registry prices;
provider-reported cost is partial at $0.02165920, and conservative budget
accounting is $0.171576.

Replay is offline with an isolated prepared database:

```sh
RAILS_ENV=test DATABASE_URL=sqlite3:/tmp/desires-dialogue-replay.sqlite3 bin/rails db:prepare db:seed
RAILS_ENV=test DATABASE_URL=sqlite3:/tmp/desires-dialogue-replay.sqlite3 bin/rails runner db/eval/desires-dialogue-20260919/replay.rb
```
