# Re-baselining the benches after the checked-in worlds gained arcs

Every checked-in world gained a `quests:` block, and the items its arc needs.
That moved what the prompt, classifier, realization and inscription benches
stage, so their kept sets stopped being baselines for this tree and the tests
that hold them to it failed. The owner approved re-buying them: the priced sets
under a stop-rather-than-exceed ceiling (first $2.00, raised by the owner to
$2.75 when it stopped the realization run), the cascade sets and the final
classifier set under their own cap (first $1.00, raised to $1.20), bracketed by OpenRouter credit readings. No prompt, schema, sampling
parameter or scorer changed.

## Spend

| group | actual | how it is known |
|---|---:|---|
| priced sets | **$0.977590** | provider-reported charge on every settled call (`receipts.json`, `summarize.py`) |
| cascade sets, and the final classifier set | **$1.039500** | OpenRouter credit readings (`credit-readings.log`), in three brackets below |
| **total** | **$2.017090** | |

The cascade group's cap was $1.00, raised by the owner to $1.20 for the final
classifier set. Its three brackets:

- the two cascade sets: 59.583860295 -> 59.962051233, $0.378191, of which
  $0.197911 is provider-reported Mistral escalations (`cascade-receipts.json`);
- a first attempt at the final classifier set, stopped by its own ledger at
  552 of 1373 calls and not resumable: 59.962051233 -> 60.154424033, $0.192373
  (`classifier-final-receipts.json`);
- the final classifier set, one call at a time: 60.154424033 -> 60.623360273,
  $0.468936, equal to its provider-reported receipts
  (`classifier-final-rerun-receipts.json`).

Priced sets, per set: classifier $0.323243, main prompt $0.198463, realization
$0.360226 (plus $0.063227 settled on the run the ceiling stopped), inscription
$0.026620, and $0.005811 on the first main-prompt attempt, stopped when its
harness could not read RubyLLM 2's token fields.

Six calls were in flight when a run stopped and left no usage record, no
generation id to look their charge up by, and no credit reading from before the
priced runs to bracket them. Each stays accounted at its full $0.21
reservation, which is why the ceiling was enforced against $2.280508 while the
settled charges total $0.977590. The cascade delta is only that group's spend
if nothing else on the shared account was spending; the TypeSafe-direct System
One requests appear in no reading at all.

## What moved beyond noise

- **main prompt** (`prompt-2026-09-26` vs `prompt-2026-09-10`): NOISE on every
  check; latency and `commitments` REAL.
- **realization** (`realization-2026-09-26` vs `desires-scale-20260920`): NOISE
  on every check but `proposal_refused` 0.107 -> 0.000, REAL; latency REAL.
- **inscription**: the same requests byte for byte, and the same figures.
- **classifier** (`classifier-2026-09-26`): REAL worse on the old labels, all of
  it three lines labelled before the writ existed; NOISE on strict accuracy,
  accuracy and misses on the new ones, refusal agreement REAL slightly worse.
  `classifier-misses.txt`, `classifier_positions.rb` and `rescore.rb` are the
  offline diagnosis.
- **cascade** (`classifier-cascade-state-20260927`): its lead over the model
  call alone is inside the noise on the worlds with arcs; intent accuracy REAL
  worse.
- **classifier after the merge** (`classifier-2026-09-27`, `throw` in the enum on
  the worlds with arcs): NOISE on every figure against
  `classifier-throw-after-20260926`.

## Files

`run.rb` is the spend guard every paid call went through; `summarize.py`
recomputes the per-set spend; the `*-run.log` and `*-comparison*.log` files are
the runs and the verdicts.
