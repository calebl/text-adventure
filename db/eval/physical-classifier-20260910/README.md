# Initial classifier candidate, not promoted

This package preserves the first R02 classifier confirmation after rebasing onto
the fresh main classifier baseline. It is evidence for a corrective change:
intent accuracy regressed even after excluding every amended label. A revised
candidate must use a separate package and leave these paid results intact.
`initial-candidate.json` hashes the fixed inputs and results; `source/` retains
the exact classifier and corrected corpus at this boundary.

The run used the existing `Eval::Classifier::Bench#read`, `Corpus::Answer`,
`Bench::Pass`, `Result` and `Comparison`, on the unchanged pinned
`mistralai/mistral-medium-3.1` through OpenRouter. All 343 cases were read four
times, plus one warmup: 1,373 calls, no provider failures or rotations. Four calls
could overlap. The shared $4 ledger accounted $0.318219 for this study;
provider-reported and registry-priced usage were $0.31764296. Unknown charges
from other studies remain in that shared ledger.

Before buying, the runner captured all 343 complete actual-ID requests and the
warmup, including system, user, schema and history. A gate checked exact equality
before every `BaseAgent` call and permitted only one call per reading. The
reviewed requests file SHA-256 was
`c7e81d737f0497c8c0b73ecf2fd646c271374b9183fe3b0a50a10abbc086141b`.
Every completed answer was flushed and fsynced before it counted as complete;
resume preserves failures. Raw requests, parsed provider answers, actual model,
latency and usage receipts survive in `readings.jsonl.gz`.

The classifier identity instrument now captures the actual schema, including
physical tokens. Identity v2 `30e17bf2d3e3c210` normalizes only known action-list
keys and schema enum values to complete named bindings. Player text, schema
descriptions, unrelated numbers and all paid requests stay literal. This is a
versioned measurement adapter change, not an unchanged manifest or a claim that
every runtime request is covered by the designated identity case.

The purchase used corpus digest `19ff8059259231dc`. Semantic review identified
four further label-only corrections before inspecting outcome tallies: three
clear handovers are offers, and opening a door alone does not ask to cross it.
`label-amendments.json` records each original and corrected row. Rescoring those
same calls gives final 343-case digest `abc2535c473693d9`. An offline replay
confirmed all 344 exact requests remained unchanged after the label amendments.
No calls were repurchased. The earlier index handover correction and these four
changes are all retained as historical-label misses in `historical-339/`.

The current 343-case strict accuracy ranges from 93.43% to 94.81%. It has no
matched 343-case before. `historical-339/` projects the same answers onto the
original, byte-preserved main339 corpus, digest `2155073129d29086`.
`comparison.json` uses the ordinary stored-summary comparison: overall and
intent accuracy are REAL lower, strict accuracy is INCONCLUSIVE, closed-set
misses are REAL fewer, refusal agreement and failures are NOISE. Latency
verdicts are suppressed because the before used concurrency two and this run
used four.

The tracked original run log named its full output directory. That file still
contained all four repetitions; its exact bytes are now kept as
`historical-before-full.json.gz`. `audit.rb` validates every full-pass metric
against the unchanged main summary, then feeds the old recorded flags and the
new scored answers through the existing `Bench::Pass` arithmetic. Excluding the
same five amended IDs leaves 334 cases and 280 strict cases per repetition.
The ordinary exact rank test reports:

| Unchanged-case metric | Before median | After median | Verdict |
| --- | ---: | ---: | --- |
| Strict accuracy | 94.46% | 93.75% | NOISE, p=.342857 |
| Overall accuracy | 94.61% | 94.01% | NOISE, p=.171429 |
| Intent accuracy | 98.50% | 96.86% | REAL worse, p=.028571 |
| Closed-set misses | 12.5 | 9 | REAL fewer, p=.028571 |

Refusal agreement and failures are NOISE. `audit.json` retains every per-pass
value, full verdicts and the complete list of current-label mistakes. The
change therefore cannot be defended as merely a relabeling effect. Concrete
regressions include:

- “hang the slate on the post and leave it there”: correct drop in all four
  before readings; now three refused use attempts and one unasked offer to Neb.
- “go through to the copy room”: correctly unresolved in all four before
  readings; now two readings choose the existing Ward Office 12 instead.
- “read the slate again in front of them”: correct examine in all four before
  readings; now four refused use attempts.

Other serious mistakes predate this candidate. “give him the index” selected
the wrong daybook in all four before readings and still does; the new branch
offers it instead of dropping it. “take a blank writ out of the press” selected
the filing press itself in all four readings on both sides. Closed enums keep
answers within the offered records; they do not establish that the player
authorized the selected record or action.

Replay both retained scoring views, the historical comparison and the unchanged
subset audit without a provider or paid database:

```sh
RAILS_ENV=test DATABASE_URL=sqlite3:/tmp/classifier-replay.sqlite3 \
  bin/rails runner db/eval/physical-classifier-20260910/replay.rb
```

Use a prepared isolated test database. These are static classifier decisions,
not whole-turn state changes or prose verification. The separate physical
corpus in `../physical-20260910/` measures the matched R02 action paths. The
initial generic benchmark remains useful precisely because it exposed regressions
outside those targeted cases.
