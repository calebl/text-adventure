# Adversarial review — repair verification

The NPC action path and turn integrity fixes are integrated. All 3,881 tests pass. Live NPC cases now apply their promised state changes; arrival prose still sometimes contradicts inventory, so that finding remains partial. New deterministic notices expose crossing costs even when the narration omits them.

Original review and measured baseline: 8dd1f5c. Fix branch: fix/npc-arrival-turn-integrity-20260908. Focused model candidate: 93448ade; sequential confirmation: 57f8738f, which adds the deterministic toll view without changing model input. These temporary candidate commits identify frozen evidence, and every measured number above stays labelled with the commit it was measured on. The branch is now rebased: 337f826 sits directly on main 2ef1a20, so the place-name identity handling and the exits lab and scorer work from main are carried rather than re-measured. The suite, lint and CI gates on the rebased tree belong to the delivery pipeline and are not claimed here.

Original evidence is preserved in [the original report](original-report.md).

## Verification

- **Integrated repository suite:** 3,881 tests / 22,172 assertions; zero failures, errors or skips. Includes engine sweeps and the real turn view. Both model integrations are active in this checkout. [Evidence](integrated-suite.log)
- **Integrated static checks:** RuboCop: 523 files, no offenses. Zeitwerk and git diff --check passed. Three migration versions have no collisions with freshly fetched main (2ef1a20). [Evidence](integrated-rubocop.log)
- **Security scan:** Brakeman: zero warnings after documenting two exact File Access false positives. Both use the trusted Rails database configuration for inter-process lock paths; fixed runtime scopes and integer IDs admit no player path. The broader check remains enabled. [Evidence](integrated-brakeman.log)
- **NPC live comparison:** Five cases × four repetitions per arm. State failures: 12/20 → 0/20; displayed-prose contradictions: 6/20 → 0/20. Both REAL under the existing exact rank test, p=0.028571. No clean-run errors. [Evidence](evaluation/npc-findings.md)
- **Arrival live comparison:** Three cases × four repetitions per arm. Description contradictions: 7/12 → 1/12, INCONCLUSIVE (p=0.057143). Dead-character contradictions: 4/4 → 0/4. Strict fact acknowledgment: NOISE. Injury appeared only in summaries, prompting a deterministic UI notice. [Evidence](evaluation/arrival-findings.md)
- **Sequential live confirmation:** Unchanged first eight Salt Assizes turns × four repetitions per arm: 64 turns / 176 calls, no failures, fallback scenes, model rotations or branch divergences. Standard measured flags stay zero; richness change is NOISE. Manual reading still finds item-identity contradictions. [Evidence](evaluation/confirmation-summary.json)
- **Shared evaluation ceiling:** 320 requests including the excluded instrumentation attempt. $2.097022 conservatively accounted under the approved $3 cap; $1.467620 is retained unknown reservations, not reported billing. No further calls are planned. [Evidence](evaluation/budget-summary.json)
- **Visible crossing outcomes:** 22 tests / 76 assertions passed. Actual debug-off page rendering, playthrough isolation, duplicate delivery, escaping, preloading and a browser-view engine sweep verify the persisted toll is displayed exactly once. This text is not counted as model prose. [Evidence](toll-notice-focused-tests.log)
- **Job and browser delivery:** 44 tests / 312 assertions passed, including a job that finishes before the HTTP response and true process overlap. [Evidence](delivery-verification.log)
- **Model failure accounting:** 22 tests / 130 assertions passed. Original refusal classification is retained and fallback prose is excluded from model readings. [Evidence](evaluation-accounting.log)
- **NPC combined regressions:** 233 tests / 984 assertions passed in the candidate runner, including malformed fields, rejected retry text, validated effects and game isolation. [Evidence](pending/npc-candidate-tests.log)
- **Arrival regressions:** 52 tests / 205 assertions passed in the candidate runner. The return-after-killing-and-looting sweep reproduces the old cast defect and passes with the candidate. [Evidence](arrival-candidate.log)
- **Fleeing and onward travel (R07):** 19 tests / 86 assertions passed; restoring the original behavior causes four expected failures. The new and existing recovery sweeps pass, and seven Ruby files are RuboCop clean. [Evidence](r07-focused-tests.log)
- **Generation checkpoints (R06):** 161 tests / 573 assertions, then 15 final recovery and sweep tests / 106 assertions, passed. Covers real chat restoration, stale choices and rollback after partial writes. [Evidence](r06-final-review-tests.log)
- **Independent generation review:** 182 registry and seed-loading tests / 667 assertions passed. Two independent generator regressions / 18 assertions and the three-step reseed sweep also passed. [Evidence](r06-independent-fix-verification.log)
- **Generation through browser turns:** Five steps passed: interrupted generation, resumed entry, taking a generated item, departure and return. Ordered fixture replies detect repeating a paid detail call. [Evidence](r06-generation-sweep.log)
- **Expanded delivery and travel checks:** 63 tests / 402 assertions passed, including real-process concurrency, failure recovery, job ordering, fleeing and subsequent travel. [Evidence](expanded-delivery-tests.log)

Live results use one pinned model, four repetitions per arm and fixed fictional fixtures. They establish bounded behavior, not realistic psychology or complete prose grounding. Standard audit flags missed item-identity contradictions in both sequential arms. No scorer, corpus or older baseline was replaced; the prompt-bench adapter only preserves failed-call accounting when gameplay uses a factual fallback. The no-mistakes PR pipeline is the remaining delivery gate.

## Live comparison

OpenRouter · mistralai/mistral-medium-3.1

| Measure | Before | After | Verdict |
| --- | --- | --- | --- |
| NPC state failures | 12 / 20 | 0 / 20 | REAL; p = 0.028571 · five cases, four runs per arm |
| NPC prose contradictions | 6 / 20 | 0 / 20 | REAL; p = 0.028571 · future offers excluded |
| Arrival prose contradictions | 7 / 12 | 1 / 12 | INCONCLUSIVE; p = 0.057143 · three cases, four runs per arm |
| Arrival strict fact acknowledgment | median missing 100% | median missing 67% | NOISE; p = 0.142857 · ambiguous corpses not silently counted |
| Sequential richness | median 2.375 | median 2.188 | NOISE; p = 0.342857 · commitments per turn |

The sequential audit scored zero violations in both arms yet manual reading found the prose carrying or conflating a dropped slate. Correct engine records and a green audit do not prove the narration is true. The full prompts, receipts, readings, independent annotations and protocols are retained under db/eval/adversarial-20260909.

## R01 · Verified · NPC decisions do not become actions

NPCs choose from engine-closed actions for owned-item gifts, following/staying and ceasefires. The engine revalidates the choice and applies it before narration, validates sanitized fields before effects, and saves the conversation atomically.

- A gifted key changes only the player’s item copy; repeat gifts, foreign holders, absent actors and dead actors are rejected.
- Followers, stopped companions, deaths and spilled inventory remain local to one playthrough. Legacy companions can choose to stay immediately.
- The combined candidate tests cover a gifted key and follower surviving failed arrival narration, and rejected retry output staying out of delivered prose.
- Live fixed-fixture comparison: 12/20 state failures and 6/20 explicit prose contradictions before, zero after; four runs per side, both REAL at p=0.028571. Appropriate refusals were preserved.

**Remaining:** This verifies a bounded conversation-to-state path. It does not add autonomous goal planning, long-term relationships or a scheduler. Prose may still omit a successful effect. Newly seeded possessions on already-dead NPCs remain an inventory edge case.

## R02 · Open · Ordinary physical actions can succeed only in prose

Outside this repair batch.


**Remaining:** Define a modest set of object affordances and actions with preconditions and effects. Resolve free text into those actions or an explicit unsupported attempt. Feed the actual result into narration so an unsupported act cannot masquerade as a completed state change.

## R03 · Partial · Arrival narration contradicts the playthrough state

Normal arrivals receive authoritative per-game destination facts: living cast, bodies, carried and floor items, wounds and crossing costs. A failed renderer uses those records directly. Every claimed crossing outcome is also rendered from its toll record beneath the prose, scoped to this game.

- The original return sweep offers dead Marek as alive; the candidate’s sweep excludes him and preserves the looted item.
- Projected followers appear at the destination, while dead companions and their possessions remain where they died.
- The world-opening prompt remains unchanged when no playthrough exists.
- Live dead-resident cases: four living-dead contradictions before, zero after. Across all cases: 7/12 → 1/12 contradictions, p=0.057143; both independent reading sets and ambiguous corpse descriptions are preserved.
- The actual view and engine sweep prove a quiet arrival still displays the exact persisted crossing outcome once, even with debug disabled and under duplicate job delivery.

**Remaining:** The live aggregate prose contradiction reduction is INCONCLUSIVE, and one arrival still put a carried key back on a desk. Strict fact acknowledgment did not improve beyond noise; none of the crossing descriptions clearly stated injury. The deterministic toll notice closes visibility for crossing outcomes, while general prose verification remains open. Visit-history leakage remains R10.

## R04 · Partial · Failed turns commit partial effects and retries repeat them

Failed or blank rendering after a committed action now produces an engine-authored scene and completes retaliation, hazards and time. Streaming and attribution failures no longer interrupt those effects. Command receipts prevent duplicate delivery from replaying them.

- Failed pickup narration still records the pickup, elapsed time and one enemy response.
- Failed arrival narration completes movement and records its crossing once; redelivery adds neither another toll nor another scene.
- The failure notice no longer promises rollback. Fallback text is excluded from model-quality measurements.

**Remaining:** A worker killed during engine writes, or an unexpected engine/database failure, leaves an interrupted or failed command. It cannot replay automatically, but there is no automatic rollback or reconciliation. The UI does not independently recover a stranded worker. Incomplete new location generation now resumes on a later entry (R06).

## R05 · Verified · Concurrent turns can lose history and generate a place twice

Commands and location realization use process locks keyed to the SQLite database and record. Waiting turns reload current state, and durable form tokens return completed results on duplicate jobs. The job now broadcasts pending and final pages in order; the HTTP response carries no stale page replacement.

- Separate processes overlap two pickups: both items and both linked scenes survive. A separate database connection can write while a provider is paused.
- Two processes holding the same stale stub generate it once and reuse the persisted result.
- An immediately completed job cannot be overwritten by a late HTTP response, and duplicate completion does not introduce another pending page.

**Remaining:** The locking primitive assumes the app’s local SQLite deployment. Durable location checkpoints handle incomplete new rooms (R06); interrupted turn reconciliation remains the limit described in R04.

## R06 · Verified · A generation failure permanently marks an unfinished room complete

Unfinished generation now saves accepted detail, the exact NPC choices and accepted exits as durable checkpoints. Materialization and phase advancement commit together, so a later entry completes the missing work without repeating paid calls or duplicating nouns. A building’s layout and finalization commit together to preserve a reachable entrance after failure.

- Fault injection covers admissions, an unavailable exits provider, finalization, invalid responses and a generator waiting with stale cached choices.
- A real persisted conversation resumes without repeating detail; deleting the originating game restores the accepted exchange without copying billed token counts.
- A browser sweep interrupts first entry, resumes with only the missing exits call, takes a generated item and revisits the same room.
- Independent review fixed sanitized NPC fields that poisoned retries, stale checkpoint replay after re-seeding, and a building doorway that could bypass its unfinished parent.

**Remaining:** Older rooms already marked realized without checkpoints still require explicit repair. World exports and generation-time forks intentionally do not back up unfinished generation checkpoints.

## R07 · Verified · Fleeing combat corrupts the origin of the next journey

A fight closed after fleeing now records its closing scene at the party’s current location while preserving the battlefield on the blows. Subsequent arrivals derive route and travel time from the playthrough’s actual origin, including older inconsistent saves.

- Nineteen focused tests with 86 assertions cover fight closure, consecutive real turns, narration failure and duplicate delivery.
- A browser sweep checks a six-minute escape, a twenty-minute district journey and zero elapsed time for redelivery.
- Restoring the previous logic causes four expected regression failures, including charging one minute for the twenty-minute route.

**Remaining:** Existing per-round fight-time accounting is preserved. Historical scenes are retained; current position takes precedence when an older scene names the wrong room.

## R08 · Open · NPCs lose important experiences and are not told about their own wounds

Outside this repair batch.


**Remaining:** Maintain durable per-game relationships and salient memories with references to witnessed events. Retrieve relevant experiences, not only recent ones. Supply verified perception of injuries and conflict before asking for a response; distinguish what each NPC witnessed from global history.

## R09 · Open · The world eventually stops admitting people and items

Outside this repair batch.


**Remaining:** Bound model context and per-room generation cost independently of total world population. If a finite adventure is intended instead, make that scope explicit and ensure the arc ends before the world becomes empty by policy.

## R10 · Open · Visit history leaks between playthroughs

Outside this repair batch.


**Remaining:** Store visits per playthrough and derive recognition from those records. Preserve the shared generated geography. Decide separately whether games share a synchronized world clock or keep per-game mutable world overlays.

## R11 · Open · Scheduled world events have no consequences yet

Outside this repair batch.


**Remaining:** Give scheduled events validated effect kinds and parameters, then apply those effects idempotently and publish their observable results to affected NPCs and narration. Keep an event’s prose summary descriptive; never treat it as executable code.

## R12 · Open · Generated alternative endings cannot be selected

Outside this repair batch.


**Remaining:** Generate from a closed set of supported outcome conditions and validate that each alternative is reachable. Align outcome prose with the condition the engine can prove. Add semantic action outcomes before making successful persuasion a completion requirement.
