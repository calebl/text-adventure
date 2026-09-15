# Physical affordances: completed realization evidence

This is the complete 29-case, four-repetition realization result for the R02
generator change. It combines the 88 retained paid readings for the unchanged
22 legacy cases with 28 newly purchased readings for the seven conditional
cases added to the corpus. The old readings remain evidence from their original
source; replay proves that their current prompt, schema, and engine admissions
are unchanged rather than relabeling them as newly purchased answers.

The final set used OpenRouter's pinned
`mistralai/mistral-medium-3.1`, request identity v1
`e29ef60c86aa8ae6`, corpus digest `de57509aa1da1a37`, and four complete
repetitions. It recorded no failures, refusals, rotations, extra calls, or
omitted fields. `readings.json.gz` holds the combined full result and
`realization.json` its summary.

`comparison.txt` and `verdicts.json` are oriented **branches-to-corpus-after ->
physical-realization-20260910**: the standing old prompt is the before arm and
the R02 prompt is the after arm, on the same model and same 29-case corpus. All
behavioral checks are NOISE. Failures, refusals, and omitted fields remain zero.
The only REAL result is the neutral output-volume metric: median output tokens
increase from 21,446 to 22,357, +911 tokens per complete pass (p=.028571).
This is evidence of additional output cost, not evidence that a behavioral
check improved.

The broad realization rubric does not score whether generated items have the
new physical profiles. The targeted generator study in
`../physical-20260910/` supplies that evidence. Taken together, the targeted
improvement and this no-regression result justify promoting this package as the
realization baseline, while retaining the measured output-token increase as a
cost tradeoff.

## Provenance and offline verification

`source-manifest.json` records the producer, schemas, benchmark, corpus, and gem
versions. It also hashes every preserved legacy artifact. The old generator,
DetailSchema, and item registry hashes match the new producer; the changed
`Item.rb` hash reflects header-comment clarification only. The 22 shared YAML
cases are byte-for-byte unchanged.

Old full requests are derived from actual paid receipts. The emitted schema is
read from each receipt. Exits history uses the saved detail prompt and
`JSON.generate` of its structured answer, exactly as `Message#extract_content`
restores it. New branch requests were captured at the real generator call
boundary. The schema-aware offline fingerprint is explicitly recorded as a
derived scaffold identity and is not claimed to have been captured by the old
bench.

`replay.rb` stages each old case without a provider, restores its recorded cast
slots, and gives the current generator the saved answers. It verifies all 88
legacy readings, all 28 branch readings, the full current corpus, exact branch
request bytes, identities, admissions, summaries, and comparison. A successful
replay reports 29 rooms, four repetitions, and only `output_tokens` as
non-noise. It writes deterministic derived artifacts but makes no model calls.

With an isolated prepared and seeded test database:

```bash
RAILS_ENV=test DATABASE_URL=sqlite3:/tmp/physical-realization-replay.sqlite3 bin/rails db:prepare db:seed
RAILS_ENV=test DATABASE_URL=sqlite3:/tmp/physical-realization-replay.sqlite3 bin/rails runner db/eval/physical-realization-20260910/replay.rb
```

`LEGACY_ONLY=1` verifies only the retained old realizations. The database is
used for rolled-back staging and engine verification.

## Receipts and limitations

The completed result contains 117 reading records and 190 provider calls:
89 legacy records including the warmup, plus 28 new branch records. Their
provider/registry-priced cost is $0.26368724. `receipts.json` separately retains
one abandoned partial reading costing $0.00209308, for total experiment cost
$0.26578032 and conservative ledger accounting of $0.265874. The cumulative
ledger snapshot in that file is historical: it records the $4 authorization and
$3.546902 accounted when this package finalized; later studies and later budget
authorizations do not rewrite it.

The comparison keeps both sides on the 29-case corpus. Some legacy cast inputs
were random when originally bought, so replay restores their recorded slots
instead of drawing new people. A budget pause is reflected in latency and no
speed improvement is inferred. The broader rubric cannot substitute for the
targeted physical-profile study.
