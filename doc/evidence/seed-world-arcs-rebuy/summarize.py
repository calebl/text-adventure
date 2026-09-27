"""Spend per set from a ledger; reservations on interrupted calls are not charges.

  python3 summarize.py [receipts.json] [--write-kept]

`actual_settled_usd` is the provider-reported charge where one was reported and
the registry price otherwise; `accounted_usd` adds the full reservation kept on
every call that was in flight when a run stopped, which is what the ceiling
was enforced against.
"""
import json
import sys
from collections import defaultdict
from pathlib import Path

root = Path(__file__).resolve().parent
ledger_path = root / next((arg for arg in sys.argv[1:] if not arg.startswith('--')), 'receipts.json')
ledger = json.loads(ledger_path.read_text())
sets = defaultdict(list)
for row in ledger['calls']:
    sets[row['set']].append(row)


def total(rows, field):
    return round(sum(row.get(field) or 0 for row in rows), 6)


summary = {
    'limit_usd': ledger['limit_usd'],
    'sets': {
        name: {
            'calls_including_warmups': len(rows),
            'settled': sum(row['state'] == 'settled' for row in rows),
            'interrupted': sum(row['state'] != 'settled' for row in rows),
            'provider_reported_usd': total(rows, 'provider_cost_usd'),
            'provider_cost_available_calls': sum(row.get('provider_cost_usd') is not None for row in rows),
            'registry_priced_usd': total(rows, 'registry_cost_usd'),
            'actual_settled_usd': round(sum(row['accounted_usd'] for row in rows if row['state'] == 'settled'), 6),
            'accounted_usd': round(sum(row['accounted_usd'] for row in rows), 6),
        }
        for name, rows in sets.items()
    },
}
summary['actual_settled_total_usd'] = round(sum(s['actual_settled_usd'] for s in summary['sets'].values()), 6)
summary['accounted_total_usd'] = round(sum(s['accounted_usd'] for s in summary['sets'].values()), 6)
print(json.dumps(summary, indent=2))

if '--write-kept' in sys.argv:
    for name, receipt in summary['sets'].items():
        target = root.parents[2] / 'db' / 'eval' / name
        if not target.is_dir() or receipt['interrupted']:
            continue
        (target / 'receipts.json').write_text(json.dumps({
            'source': f'doc/evidence/seed-world-arcs-rebuy/{ledger_path.name}',
            'transport_retries': 0, **receipt,
        }, indent=2) + '\n')
        print('wrote', target / 'receipts.json')
