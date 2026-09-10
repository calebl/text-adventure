"""Recompute task spend from receipts; reservations are not actual charges."""
import json
import sys
from collections import defaultdict
from pathlib import Path

root = Path(__file__).resolve().parent
ledger = json.loads((root / 'receipts.json').read_text())
sets = defaultdict(list)
for row in ledger['calls']:
    sets[row['set']].append(row)
summary = {
    'limit_usd': ledger['limit_usd'],
    'sets': {
        name: {
            'calls_including_warmup_and_preludes': len(rows),
            'settled': sum(row['state'] == 'settled' for row in rows),
            'unknown_or_reserved': sum(row['state'] != 'settled' for row in rows),
            'registry_priced_usd': sum(row.get('registry_cost_usd') or 0 for row in rows),
            'registry_usage_upper_usd': sum(row.get('registry_usage_usd') or 0 for row in rows),
            'provider_reported_usd': sum(row.get('provider_cost_usd') or 0 for row in rows),
            'provider_cost_available_calls': sum(row.get('provider_cost_usd') is not None for row in rows),
            'accounted_usd': sum(row['accounted_usd'] for row in rows),
            'actual_models': sorted(set(row.get('actual_model') for row in rows if row.get('actual_model'))),
            'tokens': {field: sum(row.get(field) or 0 for row in rows) for field in
                       ['input_tokens', 'output_tokens', 'cached_tokens', 'cache_creation_tokens', 'thinking_tokens']},
        }
        for name, rows in sets.items()
    },
    'accounted_total_usd': sum(row['accounted_usd'] for row in ledger['calls']),
}
summary['remaining_usd'] = summary['limit_usd'] - summary['accounted_total_usd']
print(json.dumps(summary, indent=2))

if '--write-kept' in sys.argv:
    assert summary['remaining_usd'] >= 0
    for name, receipt in summary['sets'].items():
        assert receipt['unknown_or_reserved'] == 0
        target = root.parents[2] / 'db' / 'eval' / name / 'receipts.json'
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps({
            'source': 'doc/evidence/ta-bench-rebaseline-stale/receipts.json',
            'transport_retries': 0, **receipt,
        }, indent=2) + '\n')
