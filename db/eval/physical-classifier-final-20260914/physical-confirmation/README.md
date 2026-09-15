# Final physical confirmation: complete

This is the four-repetition confirmation of the unchanged seven-case physical
corpus with the final conservative classifier prompt. It ran the full
`Playthrough::Turn` path serially against a fresh database containing only the
model registry. `physical-after.json` stores all 28 turns and 60 provider
receipts. No player world, save or chat was sent.

The corpus covers drinking a healing dose, offering a requested apple, offering
food to a distrustful NPC, unlocking with a key, prying a jammed gate, burning
paper and attempting to burn stone. The classifier selected the exact supported
physical token in all 24 supported attempts and returned `use`/`nothing` for all
four unsupported stone burns. There were no failures, fallbacks, model rotations,
wrong-target selections or engine-record mismatches.

## Judgment

| Measure | Initial baseline | Prior revised | Final classifier | Initial → final verdict | Revised → final verdict |
| --- | ---: | ---: | ---: | --- | --- |
| Required recorded outcome missing | 20/28 | 0/28 | 0/28 | REAL better, p = 0.028571 | NOISE, p = 1.0 |
| Core physical prose/state contradiction | 12/28 | 0/28 | 0/28 | REAL better, p = 0.028571 | NOISE, p = 1.0 |
| Current action recast as an earlier attempt | 0/28 | 0/28 | 0/28 | NOISE, p = 1.0 | NOISE, p = 1.0 |
| Additional incidental contradiction | 7/28 | 3/28 | 3/28 | NOISE, p = 0.114286 | NOISE, p = 1.0 |
| Wrong target selected | — | 0/28 | 0/28 | — | NOISE, p = 1.0 |
| Engine record mismatch | — | 0/28 | 0/28 | — | NOISE, p = 1.0 |

The three final incidental contradictions are bounded and do not change the
requested physical effect: drink repetitions 2 and 4 narrate an empty vial on
the floor or in hand although no container remains, and failed-pry repetition 1
says the still-carried lever struck the ground. Every NPC remained in the room,
every accepted apple went to Maren, every refused apple stayed with the player,
both passage directions agreed, and no unlock or pry narration moved the player.

`manual-audit.json` binds a human judgment for every turn to a digest of its
before/after state, narration or refusal, interactions, resolved action and raw
receipts. `finalize.rb` refuses changed evidence, incomplete repetitions,
provider/model rotation, failed calls or incomplete annotations before replaying
the same `Eval::Noise` protocol used by the original physical comparison.
`comparison.json`, `receipts.json` and `run-provenance.json` are its deterministic
offline outputs.

The final classifier therefore preserves the physical-action result established
by the prior revised arm. It does not improve the remaining incidental prose
rate. Four repetitions of seven fixed fixtures on one model do not establish
general physical realism, and the audit was not blinded.

## Run and accounting

The destination was `https://openrouter.ai/api/v1/chat/completions`, pinned to
`mistralai/mistral-medium-3.1`. The user approved raising the cumulative shared
ceiling to $5 with the instruction `yes, just raise it to $5`. The arm settled
all 60 reservations and conservatively accounted $0.106813, bringing the shared
ledger to $4.191840 with no reservation left open. The model registry estimates
the calls at $0.025650. OpenRouter supplied cost metadata for 36 non-streaming
calls ($0.01789040) but omitted it for 24 streamed narration calls, so the shared
helper retained their admitted upper bounds rather than inventing a lower cost.

The completed command was:

```sh
DATABASE_URL=sqlite3:/tmp/ta-physical-classifier-final-20260915-live.sqlite3 \
EVAL_LIVE=1 REPS=4 \
EVAL_BUDGET_FILE=/tmp/text-adventure-live-eval-20260909/budget.json \
bin/rails runner db/eval/physical-classifier-final-20260914/physical-confirmation/run.rb
```

The runner's pre-send gate matched classifier and NPC requests exactly to the
inspected fixture and rebuilt dependent narration requests from the engine's
actual receipt. The live database began with no universes, stories, locations,
playthroughs, characters, items, chats or messages and 1,166 model-registry
rows. `preflight.json` pins the request and source manifests used by the live
run; those digests are historical evidence and are not regenerated.

After the run was frozen, an engine-only guard was added to refuse taking an
immovable item. That later edit changes the working-tree source hash but does not
alter this arm's prompt/request assembly. `physical-after.json` retains the
preflight source digest `f7ce9378a7bdb548ee2ec15dc487ddb3dee56619b4cc1be5a2e0354ff1369209`.

Regenerate the final comparison offline with:

```sh
bundle exec ruby db/eval/physical-classifier-final-20260914/physical-confirmation/finalize.rb
```

`validation.json` records the completed live and offline checks. The earlier
stored-answer gate replay remains useful for checking the frozen request shape;
it makes no provider calls.
