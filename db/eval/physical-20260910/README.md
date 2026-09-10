# Physical actions and generated item profiles

This corpus measures seven physical-action fixtures and three seeded room
teasers, four repetitions per arm, using `mistralai/mistral-medium-3.1` through
OpenRouter. The raw outputs retain actual inputs, descriptions, model answers,
engine state, and call receipts. The manual audit was **not blinded**. It does
not establish general NPC, physical, or world-generation realism.

`physical-before.json` is the stored baseline;
`physical-after.json` is the revised candidate. The first candidate remains in
`initial-candidate/physical-after.json`, because its narration introduced a
repeat-action mistake. The unmodified audit retains its original labels:
`before`, `after` (initial candidate), and `revised` (canonical after).
`manifest.json` maps those names and preserves source paths, byte counts, and
SHA256 digests. The source manifests preserve the baseline's physical foundation
and each candidate's changed file hashes; they are not interchangeable with a
bare Git commit. Only the current-command/post-action inventory clarification in
`Scene::Narrator::DOING[:use]` changed between the two physical candidates.

## Physical outcomes

| Failure, out of 28 samples per arm | Before | Revised after | `Eval::Noise` |
| --- | ---: | ---: | --- |
| Expected recorded effect missing | 20 | 0 | REAL, p = 0.028571 |
| Core target-effect prose/state contradiction | 12 | 0 | REAL, p = 0.028571 |
| Current action described as completed earlier | 0 | 0 | NOISE, p = 1 |
| Additional incidental contradiction | 7 | 3 | NOISE, p = 0.114286 |

The first row includes a behavioral expectation that the friendly, hungry NPC
accepts the apple she requested. A valid refusal would not itself be an engine
error. Excluding that case leaves **16/24 versus 0/24** missing effects, also
REAL at p = 0.028571. All four revised friendly offers transfer the apple to
Maren; all four distrustful offers retain it with the player. In the baseline,
friendly acceptance is described but ownership does not change.

All revised drink samples consume the dose and change HP from 43 to 51. The
maximum is 53, so these samples do not exercise the healing cap. All revised
burns retain a burned-note tombstone and the carried tinderbox. Every stone-burn
attempt is refused with both objects intact. Each unlocking opens both directed
passages while the player remains in Market and retains the key. Pry checks
17 and 18 fail against strength 12; checks 12 and 2 pass. The passages and prose
honor all four outcomes, with no crossing and no lost lever. Supplemental journal
receipts obtained through read-only SQLite queries are embedded in the audit;
replaying the comparison does not need those databases.

The first candidate recorded all effects correctly but described **8/28** fresh
commands as redundant earlier actions: all four drinks and all four burns. The
revised narration performs those current actions, **0/28**, REAL at
p = 0.028571 compared with the initial candidate. Both candidate arms remain
visible in `comparison.json`; this is distinct from the baseline-to-revised
0-to-0 temporal comparison.

The incidental count stays separate from the core effect count. Seven baseline
arrivals place Maren in Courtyard while her records leave her in Market. Revised
drink repetitions 1, 3 and 4 retain or discard an empty vial although carried
and floor inventories contain no container. These do not invalidate consumption
or healing. Treating empty containers as untracked props would exclude those
three conflicts; the audit preserves this interpretation explicitly. Revised
drink repetition 2 instead makes the vial disappear, an unexplained realism
issue consistent with the recorded absence. The initial candidate has one
retained-container conflict and one ambiguous “only company” cast phrase. The
scorer reports confirmed incidental counts and an upper bound including that
ambiguity, without silently treating it as a clean assertion.

These are independent single-turn fixtures. Persistence across interruptions,
revisits, repeated commands and new games is exercised separately by the
`consumption-survives-interruption-and-revisit` and
`opening-a-door-is-not-crossing-it` engine sweep scripts.

## Targeted generation

The three fixed teasers specify a healing draught and drinking-water flask,
an iron crowbar and tinderbox, and a paper note and stone paperweight. Every
required object is generated in all four repetitions of both arms.

| Correct target profile component, out of 24 objects | Before | After |
| --- | ---: | ---: |
| `use_kind` | 8 | 24 |
| `combustible` | 18 | 24 |
| Both | 4 | 24 |

Each measure is REAL at p = 0.028571 using one six-object rate per repetition.
The baseline schema lacked these fields and persisted `ordinary`/`false`
defaults. Those failures demonstrate absent engine affordances, not that the
model directly chose invalid profile enums. The generated descriptions support
`healing`, `drink`, `lever` and `firestarter`; paper is combustible and stone is
not. Wooden tinderboxes are combustible, while the tin tinderbox is not. One
candidate room also contains a correctly ordinary, noncombustible clay shard;
it is preserved but excluded from the six specified targets.

This targeted corpus does not replace `Eval::Realization` or its broader room
baseline. There is no third generation arm. The before source manifest is shared
with the physical baseline; `generation/after-inputs.json` records the changed
generation files. The unmodified generation harness contains its three teasers
and is stored once under `generation/`.

## Offline replay

From the repository root, using its configured Ruby:

```bash
ruby db/eval/physical-20260910/compare.rb
```

This makes no model calls, boots no Rails application, and needs no database or
key. It verifies the retained artifact digests, corpus/source manifests,
annotations, model failures and complete repetitions, then rewrites
`comparison.json` deterministically. `Eval::Noise` receives the actual rate from
each repetition, with its minimum run count enforced; the JSON retains those
rates and the exact verdicts. Repetitions, not individual turns or objects, are
the comparison samples. Multiple exploratory comparisons are shown without a
multiple-comparison correction.

`evaluate.rb`, `cases.json`, and `fixtures.rb` are the unchanged live physical
harness. `generation/evaluate.rb` is the unchanged live generation harness.
Executing either live harness spends money and is separate from offline replay.
It requires an explicitly authorized `EVAL_LIVE=1`, a fresh prepared/seeded
isolated test database, a new `OUT`, source/arm metadata, and the existing shared
budget ledger via `EVAL_BUDGET_FILE`. `EVAL_BUDGET_HELPER` points to the existing
`db/eval/adversarial-20260909/eval-budget-streaming-v2.rb`; the helper is not copied
here. Continuing a funded evaluation must reuse its ledger. No logs, databases,
or temporary audit-generation helper scripts are part of this package.
