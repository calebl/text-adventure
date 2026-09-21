# Objects-of-desire scale revision baseline (2026-09-20)

Four-repetition after side for the prompt revision that reframes the four
objects of desire as enduring, story-scale pressures rather than opening-scene
tasks. Schema fields, pursuit vocabulary, and length limits are unchanged (220
whole-sheet / backfill, 180 realization). Dialogue was not re-bought: its
request identity does not move.

This directory is what `Eval::Genesis::BASELINE` and
`Eval::Realization::BASELINE` name. The previous standing packages
(`desires-after`, `desires-realization-20260919`) remain on disk as before
sides.

## What the comparison says

Genesis against `desires-after`: every fidelity check is **NOISE**.

Realization against `desires-realization-20260919` (`comparison.txt`,
`verdicts.json`): people offered and take-up are **NOISE**; `omitted_fields`,
`refusals`, `failures`, and `people_short_of_the_pick` stay at zero. Accepted
**REAL** costs (exact rank test, p <= 0.05):

| Figure | Before | After | Reading |
| --- | ---: | ---: | --- |
| proposal_refused | 0.038 | 0.107 | cost |
| cap_hits | 4 | 13 | cost |
| latency_median | 7.12s | 9.20s | cost |
| latency_p95 | 17.20s | 19.90s | cost |
| output_tokens | 27,885 | 29,599 | cost |

Most cap hits land on people `appearance` and `backstory`, not the desire
fields. Output-token growth is a cost, not an improvement. The owner accepted
these costs after the four-repetition compare; blind life-scale rubric marks on
the sample board never arrived.

## Provenance and guard fields

Bought with `rake eval:genesis` / `rake eval:realization` into
`tmp/eval/desires-scale-20260920`, then compacted here. `source-manifest.json`
records producer commit, source hashes (including `character/desires.rb`),
prompt and schema identities, and the corpus digest. `run-provenance.json`
records allocation, spend, and limitations. `readings.json.gz` holds every paid
row; `realization.json` is the compact summary recomputed from those rows.

With an isolated prepared test database, the offline check makes no model call:

```sh
RAILS_ENV=test DATABASE_URL=sqlite3:/tmp/desires-scale-replay.sqlite3 bin/rails db:prepare db:seed
RAILS_ENV=test DATABASE_URL=sqlite3:/tmp/desires-scale-replay.sqlite3 bin/rails runner db/eval/desires-scale-20260920/replay.rb
```

## Contents

- `genesis.json` — four genesis repetitions on `mistralai/mistral-medium-3.1`
- `realization.json` — compact four-repetition realization summary
- `readings.json.gz` — full realization rows
- `requests.json` — branch request identity
- `receipts.json` — registry-priced per-reading receipts
- `comparison.txt` / `verdicts.json` — against `desires-realization-20260919`
- `matched-verdicts.json` — against `desires-before`
- `genesis-compare.txt` — against `desires-after`
