"""Build the reviewable PR body from kept receipts and task evidence."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent
repo = root.parents[2]
prices = json.loads((root / 'prices.json').read_text())
spend = json.loads((root / 'spend-summary.json').read_text())
sets = [
    ('Main prose', 'prompt-2026-09-10', 'main'),
    ('Classifier', 'classifier-2026-09-10', 'classifier'),
    ('Ending', 'prompt-ending-2026-09-10', 'ending'),
]
rows = []
for label, name, key in sets:
    receipt = spend['sets'][name]
    rows.append(f"| {label} | ${prices[key]:.6f} | ${receipt['registry_priced_usd']:.6f} | {receipt['calls_including_warmup_and_preludes']} |")
floor = json.loads((repo / 'db/eval/classifier-2026-09-10/offline.json').read_text())['floor']
actual = sum(row['registry_priced_usd'] for row in spend['sets'].values())
billed = sum(row['provider_reported_usd'] for row in spend['sets'].values())
billed_calls = sum(row['provider_cost_available_calls'] for row in spend['sets'].values())
body = f'''Refresh the main prose, classifier, and ending kept sets as before sides for future prompt changes. The previous main set carried stale user prompts, the classifier sets predated the current corpus and request identity, and the ending sets could not distinguish stable framing from generated prelude prose.

All new sets use `Eval::Noise::MIN_RUNS` repetitions on the pinned `mistralai/mistral-medium-3.1` arm. Current-set tests now compare request identities against offline capture. Historical sets are byte-for-byte unchanged.

Ending request v2 hashes the production scaffold across every ending case with placeholders for the preceding scene's generated description and summary. Each actual prompt and both verbatim fields remain beside that scaffold, explicitly unstable. Legacy `prompt_digest` and `prompt_stable` retain their old meaning. Tests vary prelude text and recap length, verify that the outgoing request is unchanged, and verify that changed record facts, system instructions, or schemas move the scaffold.

The classifier set includes the recomputable offline floor ({floor['accuracy']:.4f} accuracy). Offline digest output now exposes its separate system/user hashes without changing the existing request identity algorithm.

### Historical main comparison

`eval:prompt_compare BEFORE=prompt-2026-09-05 AFTER=prompt-2026-09-10` reports REAL reductions in `take_denied` and `pickup_invented`, REAL increases in `latency_median` and `latency_p95`, and NOISE for every other metric, including richness. No metric is INCONCLUSIVE. The full verdicts are in `doc/evidence/ta-bench-rebaseline-stale/main-comparison.log`.

These sets span the arrival-state block and earlier user-prompt drift. This refresh was authorized to establish future before sides; the comparison does not isolate or judge a prompt change, and no improvement is attributed to this measurement-only change.

### Spend and limits

Estimates were recorded after loading the registry in the worktree's scratch database, before paid calls. Actual token usage is priced by RubyLLM's registry; provider billing is only partly available for streamed responses.

| Instrument | Estimate | Registry-priced usage | Calls including warmups/preludes |
| --- | ---: | ---: | ---: |
{chr(10).join(rows)}

Total estimated: ${sum(prices[key] for _, _, key in sets):.6f}. Registry-priced usage: ${actual:.6f}. Conservative budget accounting: ${spend['accounted_total_usd']:.6f} against the $2 ceiling, leaving ${spend['remaining_usd']:.6f}. Provider-reported billing covers {billed_calls} calls and totals ${billed:.6f}; it is not presented as the complete bill. Every call settled. Per-call evidence and per-set receipts include warmups and ending preludes that legacy scored-scene totals omit.

The task-local guard disables transport retries to reserve each attempted request, leaves sampling parameters unchanged, and retains reservations for unknown charges. Classifier calls run at concurrency 2; prose remains serial. An initial local harness error made no provider calls and is preserved in the evidence log.

The historical alternate classifier models remain unbought. Prompts, schemas, corpus cases, seeded worlds, engine behavior, migrations, and realization sets are unchanged. No multi-turn loop was purchased because no prompt change is being judged. Generic prose checks still do not measure literary quality or faithful expression of the ending; the classifier identity covers its designated staged position rather than every runtime request.

### Validation

- `bin/rails test` (includes the engine sweep)
- `bundle exec rubocop`
- `bin/rails zeitwerk:check`
- `bin/brakeman --no-pager`

All clean. Logs, offline identities, pricing, receipts, and reproduction scripts are under `doc/evidence/ta-bench-rebaseline-stale/`.
'''
print(body)
