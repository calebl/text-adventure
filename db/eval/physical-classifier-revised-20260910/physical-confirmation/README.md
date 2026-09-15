# Physical confirmation after classifier correction

Prepared offline; no live results have been purchased for this arm. The earlier
canonical `../../physical-20260910/physical-after.json` and its original before
remain unchanged. This follow-up measures whether the corrected classifier
preserves the seven physical behaviors through the actual `Playthrough::Turn`.

The original `evaluate.rb`, `fixtures.rb` and `cases.json` are loaded directly.
There are four repetitions of seven independent fictional Cal/Maren market
turns: drink a healing dose, offer a requested apple, offer food to a distrustful
NPC, unlock a keyed gate, pry a jammed gate, burn paper, and attempt to burn stone.
The stored canonical after used 60 calls; this runner caps the arm at those 60
requests. An unexpected branch fails and is retained rather than extending the
payload to a new generation task. A refusal may use fewer calls.

`requests.json` contains every inspected system/user/schema/history request.
The classifier and NPC decision requests must match it exactly before budget
reservation. Subsequent prose requests must come from the frozen engine's own
builders for the current fixture; the NPC narrator is bound to the just-received
answer and actual action receipt. Therefore its prose prompt may differ from the
stored sample when the new NPC answer differs. No existing player saves are
loaded. Reserved numeric ID slots reproduce the baseline's closed action tokens
and dice without copying seed world records.

`preflight.json` pins application sources, factories, schema, original evaluator,
corpus, shared helper and runner files. Offline replay returns the old provider
answers only after checking the current request. All 28 turns/60 requests replay;
the only changed input is the classifier instructions in 28 requests. Engine
states, interactions and rendered outcomes match the old canonical after. This
replay is preparation, not a new model measurement.

The destination is `https://openrouter.ai/api/v1/chat/completions`, with only
`mistralai/mistral-medium-3.1`. The runner loads the existing root
`eval-budget-streaming-v2.rb` and shares the existing $4 ledger, including all
earlier charges. It does not create a replacement budget or helper. The prior
60-call arm cost $0.02286552 at recorded registry rates; reserve $0.10 for planning.
Actual answers, models, tokens and charges are retained by the original
evaluator/shared helper. The helper's conservative per-request reservation can
halt earlier than the planning estimate, particularly during concurrent work.

Once explicitly authorized, the prepared command from the repository root is:

```bash
DATABASE_URL=sqlite3:/tmp/ta-physical-classifier-revised-20260910-live.sqlite3 \
EVAL_LIVE=1 REPS=4 \
EVAL_BUDGET_FILE=/tmp/text-adventure-live-eval-20260909/budget.json \
bin/rails runner db/eval/physical-classifier-revised-20260910/physical-confirmation/run.rb
```

The named isolated database currently contains schema and the offline model
registry only. The runner records each completed reading to `physical-after.json`
and refuses an existing output or previously charged arm. Inspect any interrupted
attempt before planning a resume. No live launch is part of this preparation.

Keep the original case expectations and annotation distinctions: measured engine
effects, core prose/state contradictions, temporal errors, and incidental
contradictions remain separate. Friendly acceptance is a behavioral expectation,
not an engine requirement; a valid NPC refusal is reported separately. Compare
four complete per-repetition rates with existing `Eval::Noise`, including its
noise verdict, and retain the old before, canonical after and this confirmation
as separate arms. No labels are available for the unrun arm, and no claim of
general physical or NPC realism follows from these seven fixtures.
