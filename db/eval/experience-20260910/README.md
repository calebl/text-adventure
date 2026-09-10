# NPC experience comparison

Four fixed cases, four repetitions per arm, on the pinned
`mistralai/mistral-medium-3.1` through OpenRouter. The before arm was stored
before changing any model input. It uses commit `0696d409`; the candidate source
hashes are in `candidate-inputs.json`. Fixture digests must match across arms.
An independent review found that generic private resolutions could hide distinct
spoken instructions. The revised candidate retains attributed NPC responses in
ranking, deduplication and recall. It was evaluated again against the unchanged
before arm: the same targeted 6/16 to 0/16 result holds. The first evaluated
candidate is preserved under `initial-candidate/`; it is historical evidence,
not the current model input. `replay_prompts.rb` reproduces the revised requests
from a fresh prepared and seeded test database.

The cases exercise a real injury that wrote no Scene, an unwitnessed injury in
another room, an old betrayal followed by routine conversation, and an old
promise followed by routine conversation. Fixtures use committed rows in an
isolated database; no SQLite writer spans a provider call. The promise fixture
stages medicine already returned before the conversation, rather than claiming
the engine implemented a player-give action.

| Targeted contradiction | Before | Candidate |
| --- | ---: | ---: |
| Denies or minimizes own recorded attack | 4/4 | 0/4 |
| Trusts and lends the key despite the archived refusal | 2/4 | 0/4 |
| Claims to witness the remote attack | 0/4 | 0/4 |
| Refuses or contradicts the reminded promise | 0/4 | 0/4 |

The combined rate moved from 0.25–0.50 per repetition to 0.00: **REAL**, exact
permutation p = 0.028571 using `Eval::Noise`. Changes in narration and reaction
word counts were **NOISE**. All calls returned without a gameplay fallback or
instrumentation failure. The raw responses, receipts and manual labels are
stored beside this file and replay offline.

The judgments were not blinded. In the first two betrayal baseline answers the
NPC refused for an unrelated reason; these are missing context, not counted as
direct contradictions. The promise request itself reminds the NPC of the
promise. Both arms lend the key and neither mentions the medicine; this case
does not demonstrate an improvement. Neither arm claims the unwitnessed attack,
but both invent some unrelated local news. That remains a prose-verification
concern outside the targeted metric.

Memory retrieval is lexical and can miss paraphrases. Archived thoughts are
attributed beliefs, not proof of world events. The engine still validates the
chosen action against the current records. This corpus does not establish
general NPC realism. Deterministic tests and the
`npc-experience-survives-small-talk` engine sweep separately verify the supplied
facts, source isolation, persisted retrieval and actual state effects.

## Replay and reproduce

Free comparison, with an isolated prepared test database:

```bash
RAILS_ENV=test DATABASE_URL=sqlite3:/tmp/experience-score.sqlite3 bin/rails db:prepare
RAILS_ENV=test DATABASE_URL=sqlite3:/tmp/experience-score.sqlite3 bin/rails runner db/eval/experience-20260910/compare.rb
```

`evaluate.rb` is the one live harness. It requires `EVAL_LIVE=1`, a key, an
explicit isolated `DATABASE_URL`, `OUT` naming a new result file,
`EVAL_SOURCE_SHA`, `EVAL_ARM`, `EVAL_BUDGET_FILE`, and `EVAL_BUDGET_HELPER` pointing
to the existing `db/eval/adversarial-20260909/eval-budget-streaming-v2.rb`.
Prepare and seed that database offline first. The helper pins the approved
model, reserves before each call, and stops before exceeding its shared limit.
Use the existing ledger when continuing an authorized evaluation; never reset
it to manufacture a fresh budget. `budget-summary.json` distinguishes this
experiment's conservative accounting from the cumulative shared allowance.

The generic single-turn prompt bench excludes conversations because they cost
two calls; this corpus measures the actual `InteractionAgent` path. Its fixtures
and predeclared expectations are in `cases.json`; the scorer checks completeness,
model failures and identical fixtures before producing a verdict.
