# Realization branch coverage

The corpus adds fixed record staging for unbound quest targets, named siblings,
filled item allowances, the exported door/stair plan, and a missing-chat retry
of an accepted detail exchange. Producer prompts and schemas remain untouched.

`Branches` stages the records; `BranchRequests` captures system, user, emitted
schema and ordered history in the shared request identity shape. Its designated
request is the first purchased call of each new case. For the retry this is
exits with the restored structured detail. The full paid readings also retain
subsequent requests with their particular generated assistant histories. The
legacy designation stays fixed; branch requests are independently checked
against HEAD and the paid inputs in `KeptSetTest`.

The quest check reads whether admission bound the requested target before
`Quest::Deadline` can supply an omitted target itself. `finalize.rb` recovers
that receipt by replaying the purchased structured answers through the engine,
without model calls, and rescores the exits-only scanned count. `admissions.json`
records this offline derivation. No purchased answer is changed. It reports
optional request take-up, not a requirement that every room provide the target.
The place case names an existing interior room; people and things are admitted
inside that room. The engine owns matching and target types. Saturated-item
proposals remain judgeable for over-allowance; refusal is only judgeable if the
answer actually proposes something. Retry fixture detail is input, excluded
from paid-answer checks and token counts.

Wall-specific door prose remains unavailable, as Firstmate resolved under
`wall-check-scope`. The geometry fixture detects the instruction wording; it
does not reinstate the rejected prose parser. Natural quest fit, room-name
quality, the meaning of readable words, and wall/door prose beyond record
checks belong to the labs.

## Reproduce the evidence

- `bin/rails eval:realization_digest`: legacy and branch request identities.
- `bin/rails runner doc/evidence/ta-bench-realization-branches/replay.rb`:
  rebuild the unchanged-case comparison and new-case figures from kept readings.
- `bin/rails eval:realization_compare BEFORE=exits-quantifier-after AFTER=branches-to-corpus-after`:
  full-corpus comparison, with the corpus-mismatch warning it must carry.
- After replay: `bin/rails eval:realization_compare BEFORE=exits-quantifier-after AFTER=branches-to-corpus-legacy`:
  compare only the original cases, after checking their corpus digest against
  the historical set. This is the comparison that can legitimately say NOISE.

`estimate.json` records refreshed registry pricing before purchase. The kept
`receipts.json` records actual token-priced spend including warm-up. `buy.rb`
is the purchase script, not an offline replay command: it refuses to overwrite
the set and reserves worst-case registry token costs before each room.
`readings.json.gz` keeps complete answers, facts and requests for offline
rescoring. Historical sets are unchanged.

The sibling identity work is read and uses compatible component names, but this
branch has no dependency on the open sibling branches. It does not repeat their
people-direction scrub change. Dialogue and genesis remain separate instruments.

## Purchase incident

The first attempt answered its cases but failed before export: a result class
loaded late in the long-lived process saw a scorer version loaded earlier.
Those rolled-back answers were lost. `failed-export.txt` and
`failed-export-receipts.json` retain the failure and its spend. The replacement
run preloaded the measurement classes, froze code until export, and journaled
each full reading immediately. The kept receipts include both attempts; only
the complete replacement set supplies benchmark figures.
